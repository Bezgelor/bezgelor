defmodule BezgelorData.Store do
  @moduledoc """
  ETS-backed storage for game data.

  Each data type gets its own ETS table for fast concurrent reads.
  Data is loaded at application startup from ETF files (compiled from JSON).

  ## Concurrency Model

  This module uses ETS (Erlang Term Storage) for storing static game data.
  The concurrency model is designed for a write-once, read-many pattern:

  ### Table Configuration

  All ETS tables are created with the following options:
  - `:named_table` - Tables are accessible by name globally
  - `:set` - Each key has at most one entry (O(1) lookup)
  - `:public` - Any process can read from the tables
  - `read_concurrency: true` - Optimized for concurrent reads

  ### Write Safety

  Writes are only performed during application startup by the Store GenServer.
  No writes should occur after initialization is complete. This is safe because:

  1. **Single Writer**: Only the Store GenServer writes to tables during `init/1`
  2. **Atomic Writes**: ETS inserts are atomic per-row
  3. **No Updates**: Data is static and never modified after loading

  ### Read Safety

  Reads are safe from any process at any time:

  1. **Concurrent Reads**: ETS supports unlimited concurrent readers
  2. **No Locks**: `read_concurrency: true` eliminates reader locks
  3. **No Copying**: Data is read directly from shared ETS storage

  ### Thread Safety Guarantees

  - `:ets.lookup/2` is always safe for concurrent access
  - `:ets.insert/2` is atomic per-row
  - No coordination needed between readers
  - Writers are serialized through the GenServer (startup only)

  ### Performance Characteristics

  - Read: O(1) for direct key lookup
  - Read: O(n) for full table scans (via `:ets.tab2list/1`)
  - Memory: Data stored once, shared across all processes
  - No garbage collection pressure from read operations
  """

  use GenServer

  require Logger

  alias BezgelorData.Compiler

  @tables [
    :creatures,
    :creatures_full,
    :zones,
    :spells,
    :items,
    :item_types,
    :creation_armor_sets,
    :texts,
    :house_types,
    :housing_decor,
    :housing_fabkits,
    :titles,
    :tradeskill_professions,
    :tradeskill_schematics,
    :tradeskill_talents,
    :tradeskill_additives,
    :tradeskill_nodes,
    :tradeskill_work_orders,
    :public_events,
    :world_bosses,
    :event_spawn_points,
    :event_loot_tables,
    :instances,
    :instance_bosses,
    :mythic_affixes,
    # PvP data
    :battlegrounds,
    :arenas,
    :warplot_plugs,
    # Spawn data
    :creature_spawns,
    # Quest data (extracted from client)
    :quests,
    :quest_objectives,
    :quest_rewards,
    :quest_categories,
    :quest_hubs,
    # NPC/Vendor data
    :npc_vendors,
    :vendor_inventories,
    :creature_affiliations,
    # Dialogue data
    :gossip_entries,
    :gossip_sets,
    # Achievement data
    :achievements,
    :achievement_categories,
    :achievement_checklists,
    # Path data
    :path_missions,
    :path_episodes,
    :path_rewards,
    # Challenge data
    :challenges,
    :challenge_tiers,
    # World location data
    :world_locations,
    :bind_points,
    # Prerequisites
    :prerequisites,
    # Loot data
    :loot_tables,
    :creature_loot_rules,
    # Harvest node loot
    :harvest_loot,
    # Character creation templates
    :character_creations,
    # Character customization (label/value -> slot/displayId mapping)
    :character_customizations,
    # Item display source entries (for level-scaled item visuals)
    :item_display_sources,
    # Item display data (model paths, textures)
    :item_displays,
    # Patrol paths for creature movement
    :patrol_paths,
    # Spline data (from client Spline2.tbl and Spline2Node.tbl)
    :splines,
    :spline_nodes,
    # Entity spline mappings (from NexusForever.WorldDatabase)
    :entity_splines
  ]

  # Secondary index tables for efficient lookups by foreign key
  # Maps: foreign_key_value -> [primary_id, ...]
  @index_tables [
    :schematics_by_profession,
    :talents_by_profession,
    :nodes_by_profession,
    :work_orders_by_profession,
    :events_by_zone,
    :world_bosses_by_zone,
    :instances_by_type,
    :bosses_by_instance,
    # Quest indexes
    :quests_by_zone,
    :quest_objectives_by_quest,
    :quest_rewards_by_quest,
    # NPC/Vendor indexes
    :vendors_by_creature,
    :vendors_by_type,
    # Dialogue indexes
    :gossip_entries_by_set,
    # Achievement indexes
    :achievements_by_category,
    :achievements_by_zone,
    # Path indexes
    :path_missions_by_episode,
    :path_missions_by_type,
    :path_episodes_by_zone,
    # Challenge indexes
    :challenges_by_zone,
    :challenge_tiers_by_challenge,
    # World location indexes
    :world_locations_by_world,
    :world_locations_by_zone,
    # Character customization indexes (race, sex) -> list of customization entries
    :customizations_by_race_sex,
    # Item display source entries indexed by source_id for efficient lookup
    :display_sources_by_source_id,
    # Spline nodes indexed by spline_id for efficient lookup
    :spline_nodes_by_spline
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get an item by ID from the specified table.
  """
  @spec get(atom(), non_neg_integer()) :: {:ok, map()} | :error
  def get(table, id) do
    case :ets.lookup(table_name(table), id) do
      [{^id, data}] -> {:ok, data}
      [] -> :error
    end
  end

  @doc """
  List all items from the specified table.

  Note: For large tables, consider using `list_paginated/2` instead to avoid
  loading 50,000+ items into memory at once.
  """
  @spec list(atom()) :: [map()]
  def list(table) do
    :ets.tab2list(table_name(table))
    |> Enum.map(fn {_id, data} -> data end)
  end

  @default_page_size 100

  @doc """
  List items with pagination.

  Returns `{items, continuation}` where continuation is nil when no more pages.
  Uses ETS match with continuation for memory-efficient iteration over large tables.

  ## Example

      {items, cont} = Store.list_paginated(:items, 50)
      {more_items, cont2} = Store.list_continue(cont)
  """
  @spec list_paginated(atom(), pos_integer()) :: {[map()], term() | nil}
  def list_paginated(table, limit \\ @default_page_size) do
    table_name = table_name(table)

    case :ets.match(table_name, {:"$1", :"$2"}, limit) do
      {matches, continuation} ->
        items = Enum.map(matches, fn [_id, data] -> data end)
        {items, continuation}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  Continue paginated iteration from a previous call.

  Returns `{items, continuation}` where continuation is nil when no more pages.
  """
  @spec list_continue(term()) :: {[map()], term() | nil}
  def list_continue(nil), do: {[], nil}

  def list_continue(continuation) do
    case :ets.match(continuation) do
      {matches, new_continuation} ->
        items = Enum.map(matches, fn [_id, data] -> data end)
        {items, new_continuation}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  List items matching a filter with pagination.

  Uses `:ets.select/3` for efficient server-side iteration with filtering
  applied in-memory. For simple equality filters on indexed fields,
  consider using a specific query function instead.
  """
  @spec list_filtered(atom(), (map() -> boolean()), pos_integer()) :: {[map()], term() | nil}
  def list_filtered(table, filter_fn, limit \\ @default_page_size) do
    table_name = table_name(table)

    # Use match_spec to retrieve all values, then filter in Elixir
    # This is still more efficient than tab2list as we process in batches
    match_spec = [{
      {:"$1", :"$2"},
      [],
      [:"$2"]
    }]

    case :ets.select(table_name, match_spec, limit) do
      {items, continuation} ->
        filtered = Enum.filter(items, filter_fn)
        {filtered, {:filtered, continuation, filter_fn}}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  Continue filtered pagination from a previous call.
  """
  @spec list_filtered_continue(term()) :: {[map()], term() | nil}
  def list_filtered_continue(nil), do: {[], nil}

  def list_filtered_continue({:filtered, continuation, filter_fn}) do
    case :ets.select(continuation) do
      {items, new_continuation} ->
        filtered = Enum.filter(items, filter_fn)
        {filtered, {:filtered, new_continuation, filter_fn}}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  Collect all pages into a list (convenience function for small filtered results).

  Use with caution on large tables - this will load all matching items into memory.
  """
  @spec collect_all_pages({[map()], term() | nil}, (term() -> {[map()], term() | nil})) :: [map()]
  def collect_all_pages({items, nil}, _continue_fn), do: items

  def collect_all_pages({items, continuation}, continue_fn) do
    items ++ collect_all_pages(continue_fn.(continuation), continue_fn)
  end

  @doc """
  Get the count of items in a table.
  """
  @spec count(atom()) :: non_neg_integer()
  def count(table) do
    :ets.info(table_name(table), :size)
  end

  @doc """
  Reload data from files. Used for development/testing.
  """
  @spec reload() :: :ok
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # Tradeskill-specific queries

  @doc """
  Get a profession by ID.
  """
  @spec get_profession(non_neg_integer()) :: {:ok, map()} | :error
  def get_profession(id), do: get(:tradeskill_professions, id)

  @doc """
  Get all professions of a specific type.
  """
  @spec get_professions_by_type(atom()) :: [map()]
  def get_professions_by_type(type) when type in [:crafting, :gathering] do
    type_str = Atom.to_string(type)

    list(:tradeskill_professions)
    |> Enum.filter(fn p -> p.type == type_str end)
  end

  @doc """
  Get a schematic by ID.
  """
  @spec get_schematic(non_neg_integer()) :: {:ok, map()} | :error
  def get_schematic(id), do: get(:tradeskill_schematics, id)

  @doc """
  Get all schematics for a profession.

  Uses secondary index for O(1) lookup instead of scanning all schematics.
  """
  @spec get_schematics_for_profession(non_neg_integer()) :: [map()]
  def get_schematics_for_profession(profession_id) do
    ids = lookup_index(:schematics_by_profession, profession_id)
    fetch_by_ids(:tradeskill_schematics, ids)
  end

  @doc """
  Get schematics available at a skill level.
  """
  @spec get_available_schematics(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_available_schematics(profession_id, skill_level) do
    list(:tradeskill_schematics)
    |> Enum.filter(fn s ->
      s.profession_id == profession_id and s.min_level <= skill_level
    end)
  end

  @doc """
  Get a talent by ID.
  """
  @spec get_talent(non_neg_integer()) :: {:ok, map()} | :error
  def get_talent(id), do: get(:tradeskill_talents, id)

  @doc """
  Get all talents for a profession.

  Uses secondary index for O(1) lookup instead of scanning all talents.
  """
  @spec get_talents_for_profession(non_neg_integer()) :: [map()]
  def get_talents_for_profession(profession_id) do
    ids = lookup_index(:talents_by_profession, profession_id)

    fetch_by_ids(:tradeskill_talents, ids)
    |> Enum.sort_by(fn t -> {t.tier, t.id} end)
  end

  @doc """
  Get an additive by ID.
  """
  @spec get_additive(non_neg_integer()) :: {:ok, map()} | :error
  def get_additive(id), do: get(:tradeskill_additives, id)

  @doc """
  Get additive by item ID.
  """
  @spec get_additive_by_item(non_neg_integer()) :: {:ok, map()} | :error
  def get_additive_by_item(item_id) do
    case Enum.find(list(:tradeskill_additives), fn a -> a.item_id == item_id end) do
      nil -> :error
      additive -> {:ok, additive}
    end
  end

  @doc """
  Get a node type by ID.
  """
  @spec get_node_type(non_neg_integer()) :: {:ok, map()} | :error
  def get_node_type(id), do: get(:tradeskill_nodes, id)

  @doc """
  Get all node types for a profession.

  Uses secondary index for O(1) lookup instead of scanning all nodes.
  """
  @spec get_node_types_for_profession(non_neg_integer()) :: [map()]
  def get_node_types_for_profession(profession_id) do
    ids = lookup_index(:nodes_by_profession, profession_id)
    fetch_by_ids(:tradeskill_nodes, ids)
  end

  @doc """
  Get node types for a level range.
  """
  @spec get_node_types_for_level(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_node_types_for_level(profession_id, level) do
    list(:tradeskill_nodes)
    |> Enum.filter(fn n ->
      n.profession_id == profession_id and n.min_level <= level and n.max_level >= level
    end)
  end

  @doc """
  Get a work order template by ID.
  """
  @spec get_work_order_template(non_neg_integer()) :: {:ok, map()} | :error
  def get_work_order_template(id), do: get(:tradeskill_work_orders, id)

  @doc """
  Get all work order templates for a profession.

  Uses secondary index for O(1) lookup instead of scanning all work orders.
  """
  @spec get_work_orders_for_profession(non_neg_integer()) :: [map()]
  def get_work_orders_for_profession(profession_id) do
    ids = lookup_index(:work_orders_by_profession, profession_id)
    fetch_by_ids(:tradeskill_work_orders, ids)
  end

  @doc """
  Get available work order templates at a skill level.
  """
  @spec get_available_work_orders(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_available_work_orders(profession_id, skill_level) do
    list(:tradeskill_work_orders)
    |> Enum.filter(fn wo ->
      wo.profession_id == profession_id and wo.min_level <= skill_level
    end)
  end

  # Public Events queries

  @doc """
  Get a public event definition by ID.
  """
  @spec get_public_event(non_neg_integer()) :: {:ok, map()} | :error
  def get_public_event(id), do: get(:public_events, id)

  @doc """
  Get all public events for a zone.

  Uses secondary index for O(1) lookup instead of scanning all events.
  """
  @spec get_zone_public_events(non_neg_integer()) :: [map()]
  def get_zone_public_events(zone_id) do
    ids = lookup_index(:events_by_zone, zone_id)
    fetch_by_ids(:public_events, ids)
  end

  @doc """
  Get a world boss definition by ID.
  """
  @spec get_world_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_world_boss(id), do: get(:world_bosses, id)

  @doc """
  Get all world bosses for a zone.

  Uses secondary index for O(1) lookup instead of scanning all bosses.
  """
  @spec get_zone_world_bosses(non_neg_integer()) :: [map()]
  def get_zone_world_bosses(zone_id) do
    ids = lookup_index(:world_bosses_by_zone, zone_id)
    fetch_by_ids(:world_bosses, ids)
  end

  @doc """
  Get spawn points for a zone.
  """
  @spec get_event_spawn_points(non_neg_integer()) :: {:ok, map()} | :error
  def get_event_spawn_points(zone_id), do: get(:event_spawn_points, zone_id)

  @doc """
  Get specific spawn point group.
  """
  @spec get_spawn_point_group(non_neg_integer(), String.t()) :: [map()]
  def get_spawn_point_group(zone_id, group_name) do
    case get_event_spawn_points(zone_id) do
      {:ok, data} -> Map.get(data.spawn_point_groups, group_name, [])
      :error -> []
    end
  end

  @doc """
  Get an event loot table by ID.
  """
  @spec get_event_loot_table(non_neg_integer()) :: {:ok, map()} | :error
  def get_event_loot_table(id), do: get(:event_loot_tables, id)

  @doc """
  Get loot table for an event.
  """
  @spec get_loot_table_for_event(non_neg_integer()) :: {:ok, map()} | :error
  def get_loot_table_for_event(event_id) do
    case Enum.find(list(:event_loot_tables), fn lt -> lt.event_id == event_id end) do
      nil -> :error
      loot_table -> {:ok, loot_table}
    end
  end

  @doc """
  Get loot table for a world boss.
  """
  @spec get_loot_table_for_world_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_loot_table_for_world_boss(boss_id) do
    case Enum.find(list(:event_loot_tables), fn lt -> lt[:world_boss_id] == boss_id end) do
      nil -> :error
      loot_table -> {:ok, loot_table}
    end
  end

  @doc """
  Get tier drops from a loot table.
  """
  @spec get_tier_drops(non_neg_integer(), atom()) :: [map()]
  def get_tier_drops(loot_table_id, tier) when tier in [:gold, :silver, :bronze, :participation] do
    case get_event_loot_table(loot_table_id) do
      {:ok, loot_table} ->
        tier_key = Atom.to_string(tier)
        Map.get(loot_table.tier_drops, String.to_atom(tier_key), [])

      :error ->
        []
    end
  end

  # Instance/Dungeon queries

  @doc """
  Get an instance definition by ID.
  """
  @spec get_instance(non_neg_integer()) :: {:ok, map()} | :error
  def get_instance(id), do: get(:instances, id)

  @doc """
  Get all instances of a specific type.

  Uses secondary index for O(1) lookup instead of scanning all instances.
  """
  @spec get_instances_by_type(String.t()) :: [map()]
  def get_instances_by_type(type) when type in ["dungeon", "adventure", "raid", "expedition"] do
    ids = lookup_index(:instances_by_type, type)
    fetch_by_ids(:instances, ids)
  end

  @doc """
  Get instances available for a player level.
  """
  @spec get_available_instances(non_neg_integer()) :: [map()]
  def get_available_instances(player_level) do
    list(:instances)
    |> Enum.filter(fn i -> i.min_level <= player_level and i.max_level >= player_level end)
  end

  @doc """
  Get instances with a specific difficulty.
  """
  @spec get_instances_with_difficulty(String.t()) :: [map()]
  def get_instances_with_difficulty(difficulty) do
    list(:instances)
    |> Enum.filter(fn i -> difficulty in i.difficulties end)
  end

  @doc """
  Get an instance boss definition by ID.
  """
  @spec get_instance_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_instance_boss(id), do: get(:instance_bosses, id)

  @doc """
  Get all bosses for an instance.

  Uses secondary index for O(1) lookup instead of scanning all bosses.
  """
  @spec get_bosses_for_instance(non_neg_integer()) :: [map()]
  def get_bosses_for_instance(instance_id) do
    ids = lookup_index(:bosses_by_instance, instance_id)

    fetch_by_ids(:instance_bosses, ids)
    |> Enum.sort_by(fn b -> b.order end)
  end

  @doc """
  Get required bosses for an instance (non-optional).
  """
  @spec get_required_bosses(non_neg_integer()) :: [map()]
  def get_required_bosses(instance_id) do
    get_bosses_for_instance(instance_id)
    |> Enum.filter(fn b -> not b.is_optional end)
  end

  @doc """
  Get optional bosses for an instance.
  """
  @spec get_optional_bosses(non_neg_integer()) :: [map()]
  def get_optional_bosses(instance_id) do
    get_bosses_for_instance(instance_id)
    |> Enum.filter(fn b -> b.is_optional end)
  end

  @doc """
  Get a mythic affix by ID.
  """
  @spec get_mythic_affix(non_neg_integer()) :: {:ok, map()} | :error
  def get_mythic_affix(id), do: get(:mythic_affixes, id)

  @doc """
  Get all mythic affixes.
  """
  @spec get_all_mythic_affixes() :: [map()]
  def get_all_mythic_affixes, do: list(:mythic_affixes)

  @doc """
  Get affixes available at a keystone level.
  """
  @spec get_affixes_for_level(non_neg_integer()) :: [map()]
  def get_affixes_for_level(keystone_level) do
    list(:mythic_affixes)
    |> Enum.filter(fn a -> a.min_level <= keystone_level end)
  end

  @doc """
  Get affixes by tier.
  """
  @spec get_affixes_by_tier(non_neg_integer()) :: [map()]
  def get_affixes_by_tier(tier) when tier in 1..4 do
    list(:mythic_affixes)
    |> Enum.filter(fn a -> a.tier == tier end)
  end

  @doc """
  Get the weekly affix rotation for a given week.
  Returns nil if week is out of range or data not loaded.
  """
  @spec get_weekly_affix_rotation(non_neg_integer()) :: [map()] | nil
  def get_weekly_affix_rotation(week) when week >= 1 and week <= 12 do
    # This uses a special metadata key to store rotation data
    case :ets.lookup(table_name(:mythic_affixes), :weekly_rotation) do
      [{:weekly_rotation, rotations}] ->
        rotation = Enum.find(rotations, fn r -> r.week == week end)

        if rotation do
          Enum.map(rotation.affixes, fn affix_id ->
            case get_mythic_affix(affix_id) do
              {:ok, affix} -> affix
              :error -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
        else
          nil
        end

      [] ->
        nil
    end
  end

  def get_weekly_affix_rotation(_week), do: nil

  # PvP queries

  @doc """
  Get a battleground definition by ID.
  """
  @spec get_battleground(non_neg_integer()) :: {:ok, map()} | :error
  def get_battleground(id), do: get(:battlegrounds, id)

  @doc """
  Get all battlegrounds.
  """
  @spec get_all_battlegrounds() :: [map()]
  def get_all_battlegrounds, do: list(:battlegrounds)

  @doc """
  Get battlegrounds available for a player level.
  """
  @spec get_available_battlegrounds(non_neg_integer()) :: [map()]
  def get_available_battlegrounds(player_level) do
    list(:battlegrounds)
    |> Enum.filter(fn bg -> bg.min_level <= player_level and bg.max_level >= player_level end)
  end

  @doc """
  Get battlegrounds by type.
  """
  @spec get_battlegrounds_by_type(String.t()) :: [map()]
  def get_battlegrounds_by_type(type) do
    list(:battlegrounds)
    |> Enum.filter(fn bg -> bg.type == type end)
  end

  @doc """
  Get an arena definition by ID.
  """
  @spec get_arena(non_neg_integer()) :: {:ok, map()} | :error
  def get_arena(id), do: get(:arenas, id)

  @doc """
  Get all arenas.
  """
  @spec get_all_arenas() :: [map()]
  def get_all_arenas, do: list(:arenas)

  @doc """
  Get arenas that support a specific bracket.
  """
  @spec get_arenas_for_bracket(String.t()) :: [map()]
  def get_arenas_for_bracket(bracket) do
    list(:arenas)
    |> Enum.filter(fn arena -> bracket in arena.brackets end)
  end

  @doc """
  Get arena bracket configuration.
  Returns nil if bracket data not loaded or bracket not found.
  """
  @spec get_arena_bracket(String.t()) :: map() | nil
  def get_arena_bracket(bracket) do
    case :ets.lookup(table_name(:arenas), :brackets) do
      [{:brackets, brackets}] -> Map.get(brackets, String.to_atom(bracket))
      [] -> nil
    end
  end

  @doc """
  Get arena rating rewards configuration.
  """
  @spec get_arena_rating_rewards() :: map() | nil
  def get_arena_rating_rewards do
    case :ets.lookup(table_name(:arenas), :rating_rewards) do
      [{:rating_rewards, rewards}] -> rewards
      [] -> nil
    end
  end

  @doc """
  Get a warplot plug definition by ID.
  """
  @spec get_warplot_plug(non_neg_integer()) :: {:ok, map()} | :error
  def get_warplot_plug(id), do: get(:warplot_plugs, id)

  @doc """
  Get all warplot plugs.
  """
  @spec get_all_warplot_plugs() :: [map()]
  def get_all_warplot_plugs, do: list(:warplot_plugs)

  @doc """
  Get warplot plugs by category.
  """
  @spec get_warplot_plugs_by_category(String.t()) :: [map()]
  def get_warplot_plugs_by_category(category) do
    list(:warplot_plugs)
    |> Enum.filter(fn plug -> plug.category == category end)
  end

  @doc """
  Get warplot plug categories with descriptions.
  """
  @spec get_warplot_plug_categories() :: map() | nil
  def get_warplot_plug_categories do
    case :ets.lookup(table_name(:warplot_plugs), :categories) do
      [{:categories, categories}] -> categories
      [] -> nil
    end
  end

  @doc """
  Get warplot socket layout.
  """
  @spec get_warplot_socket_layout() :: map() | nil
  def get_warplot_socket_layout do
    case :ets.lookup(table_name(:warplot_plugs), :socket_layout) do
      [{:socket_layout, layout}] -> layout
      [] -> nil
    end
  end

  @doc """
  Get warplot settings.
  """
  @spec get_warplot_settings() :: map() | nil
  def get_warplot_settings do
    case :ets.lookup(table_name(:warplot_plugs), :warplot_settings) do
      [{:warplot_settings, settings}] -> settings
      [] -> nil
    end
  end

  # Creature Spawn queries

  @doc """
  Get creature spawns for a world/zone.
  Returns a map with creature_spawns, resource_spawns, and object_spawns.
  """
  @spec get_creature_spawns(non_neg_integer()) :: {:ok, map()} | :error
  def get_creature_spawns(world_id), do: get(:creature_spawns, world_id)

  @doc """
  Get all zone spawn data.
  """
  @spec get_all_spawn_zones() :: [map()]
  def get_all_spawn_zones, do: list(:creature_spawns)

  @doc """
  Get creature spawns for a specific area within a zone.
  """
  @spec get_spawns_in_area(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_spawns_in_area(world_id, area_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} ->
        Enum.filter(zone_data.creature_spawns, fn spawn ->
          spawn.area_id == area_id
        end)

      :error ->
        []
    end
  end

  @doc """
  Get all spawns for a specific creature template ID across all zones.
  """
  @spec get_spawns_for_creature(non_neg_integer()) :: [map()]
  def get_spawns_for_creature(creature_id) do
    list(:creature_spawns)
    |> Enum.flat_map(fn zone_data ->
      Enum.filter(zone_data.creature_spawns, fn spawn ->
        spawn.creature_id == creature_id
      end)
    end)
  end

  @doc """
  Get resource spawns for a world/zone.
  """
  @spec get_resource_spawns(non_neg_integer()) :: [map()]
  def get_resource_spawns(world_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} -> zone_data.resource_spawns
      :error -> []
    end
  end

  @doc """
  Get object spawns for a world/zone.
  """
  @spec get_object_spawns(non_neg_integer()) :: [map()]
  def get_object_spawns(world_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} -> zone_data.object_spawns
      :error -> []
    end
  end

  @doc """
  Get spawn count for a world/zone.
  """
  @spec get_spawn_count(non_neg_integer()) :: non_neg_integer()
  def get_spawn_count(world_id) do
    case get_creature_spawns(world_id) do
      {:ok, zone_data} ->
        length(zone_data.creature_spawns) +
          length(zone_data.resource_spawns) +
          length(zone_data.object_spawns)

      :error ->
        0
    end
  end

  @doc """
  Get total spawn count across all zones.
  """
  @spec get_total_spawn_count() :: non_neg_integer()
  def get_total_spawn_count do
    list(:creature_spawns)
    |> Enum.reduce(0, fn zone_data, acc ->
      acc +
        length(zone_data.creature_spawns) +
        length(zone_data.resource_spawns) +
        length(zone_data.object_spawns)
    end)
  end

  # Patrol path queries

  @doc """
  Get a patrol path by name.
  Returns the path definition with waypoints, mode, speed etc.
  """
  @spec get_patrol_path(String.t()) :: {:ok, map()} | :error
  def get_patrol_path(path_name) do
    case :ets.lookup(table_name(:patrol_paths), path_name) do
      [{^path_name, data}] -> {:ok, data}
      [] -> :error
    end
  end

  @doc """
  Get all patrol paths.
  """
  @spec list_patrol_paths() :: [map()]
  def list_patrol_paths do
    table_name(:patrol_paths)
    |> :ets.tab2list()
    |> Enum.map(fn {_name, data} -> data end)
  end

  # Spline queries (from WildStar client Spline2.tbl / Spline2Node.tbl)

  @doc """
  Get a spline definition by ID.
  Returns the spline with its waypoints (nodes).
  """
  @spec get_spline(non_neg_integer()) :: {:ok, map()} | :error
  def get_spline(spline_id) do
    case get(:splines, spline_id) do
      {:ok, spline} ->
        nodes = get_spline_nodes(spline_id)
        {:ok, Map.put(spline, :nodes, nodes)}

      :error ->
        :error
    end
  end

  @doc """
  Get spline nodes for a spline ID.
  Returns nodes sorted by ordinal (waypoint order).
  """
  @spec get_spline_nodes(non_neg_integer()) :: [map()]
  def get_spline_nodes(spline_id) do
    ids = lookup_index(:spline_nodes_by_spline, spline_id)
    fetch_by_ids(:spline_nodes, ids)
    |> Enum.sort_by(& &1.ordinal)
  end

  @doc """
  Get all splines for a world/zone.
  """
  @spec get_splines_for_world(non_neg_integer()) :: [map()]
  def get_splines_for_world(world_id) do
    list(:splines)
    |> Enum.filter(fn s -> s.world_id == world_id end)
  end

  @doc """
  Find the nearest spline to a position in a given world.
  Returns {:ok, spline_id, distance} if found within max_distance, :none otherwise.

  Options:
    - max_distance: maximum distance to search (default: 5.0 units)
  """
  @spec find_nearest_spline(non_neg_integer(), {float(), float(), float()}, keyword()) ::
          {:ok, non_neg_integer(), float()} | :none
  def find_nearest_spline(world_id, {px, py, pz} = _position, opts \\ []) do
    max_distance = Keyword.get(opts, :max_distance, 5.0)

    # Get all splines for this world with their first node position
    splines_with_start =
      get_splines_for_world(world_id)
      |> Enum.map(fn spline ->
        nodes = get_spline_nodes(spline.id)

        case nodes do
          [first | _] ->
            {spline.id, {first.position0, first.position1, first.position2}}

          [] ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Find the closest spline by distance to first waypoint
    result =
      splines_with_start
      |> Enum.map(fn {spline_id, {sx, sy, sz}} ->
        distance = :math.sqrt(:math.pow(px - sx, 2) + :math.pow(py - sy, 2) + :math.pow(pz - sz, 2))
        {spline_id, distance}
      end)
      |> Enum.filter(fn {_id, dist} -> dist <= max_distance end)
      |> Enum.min_by(fn {_id, dist} -> dist end, fn -> nil end)

    case result do
      {spline_id, distance} -> {:ok, spline_id, distance}
      nil -> :none
    end
  end

  @doc """
  Build a spatial index of spline starting positions for efficient lookups.
  Returns a map of %{world_id => [{spline_id, {x, y, z}}]}.
  """
  @spec build_spline_spatial_index() :: map()
  def build_spline_spatial_index do
    list(:splines)
    |> Enum.reduce(%{}, fn spline, acc ->
      nodes = get_spline_nodes(spline.id)

      case nodes do
        [first | _] ->
          entry = {spline.id, {first.position0, first.position1, first.position2}}
          world_entries = Map.get(acc, spline.world_id, [])
          Map.put(acc, spline.world_id, [entry | world_entries])

        [] ->
          acc
      end
    end)
  end

  @doc """
  Find nearest spline using a pre-built spatial index (more efficient for batch lookups).
  """
  @spec find_nearest_spline_indexed(map(), non_neg_integer(), {float(), float(), float()}, keyword()) ::
          {:ok, non_neg_integer(), float()} | :none
  def find_nearest_spline_indexed(spatial_index, world_id, {px, py, pz}, opts \\ []) do
    max_distance = Keyword.get(opts, :max_distance, 5.0)

    case Map.get(spatial_index, world_id, []) do
      [] ->
        :none

      splines ->
        result =
          splines
          |> Enum.map(fn {spline_id, {sx, sy, sz}} ->
            distance =
              :math.sqrt(:math.pow(px - sx, 2) + :math.pow(py - sy, 2) + :math.pow(pz - sz, 2))

            {spline_id, distance}
          end)
          |> Enum.filter(fn {_id, dist} -> dist <= max_distance end)
          |> Enum.min_by(fn {_id, dist} -> dist end, fn -> nil end)

        case result do
          {spline_id, distance} -> {:ok, spline_id, distance}
          nil -> :none
        end
    end
  end

  @doc """
  Get spline as patrol path format (compatible with AI patrol system).
  Converts spline nodes to waypoints with position and pause_ms.
  """
  @spec get_spline_as_patrol(non_neg_integer()) :: {:ok, map()} | :error
  def get_spline_as_patrol(spline_id) do
    case get_spline(spline_id) do
      {:ok, spline} ->
        waypoints =
          Enum.map(spline.nodes, fn node ->
            %{
              position: {node.position0, node.position1, node.position2},
              pause_ms: trunc(node.delay * 1000)
            }
          end)

        patrol = %{
          name: "spline_#{spline_id}",
          display_name: "Spline #{spline_id}",
          world_id: spline.world_id,
          spline_type: spline.spline_type,
          waypoints: waypoints,
          mode: :cyclic,
          speed: 3.0
        }

        {:ok, patrol}

      :error ->
        :error
    end
  end

  @doc """
  Look up entity spline configuration by world_id, creature_id, and position.

  Returns {:ok, spline_config} if a matching entity spline is found, :none otherwise.
  Matches entities within 5 units of the given position (to handle minor coordinate differences).

  The spline_config contains:
  - spline_id: The spline path to follow
  - mode: SplineMode (0=OneShot, 1=BackAndForth, 2=Cyclic, etc.)
  - speed: Movement speed (units/second), -1 means use default
  - fx, fy, fz: Formation offsets from path
  """
  @spec find_entity_spline(non_neg_integer(), non_neg_integer(), {float(), float(), float()}) ::
          {:ok, map()} | :none
  def find_entity_spline(world_id, creature_id, {px, py, pz}) do
    table_name = table_name(:entity_splines)

    case :ets.lookup(table_name, world_id) do
      [{^world_id, entities}] ->
        # Find entity matching creature_id and position (within tolerance)
        match =
          Enum.find(entities, fn entity ->
            entity_creature_id = entity[:creature_id] || entity["creature_id"]
            position = entity[:position] || entity["position"]

            # Handle both list and tuple positions
            {ex, ey, ez} =
              case position do
                [x, y, z] -> {x, y, z}
                {x, y, z} -> {x, y, z}
                _ -> {0, 0, 0}
              end

            entity_creature_id == creature_id and
              position_match?({px, py, pz}, {ex, ey, ez}, 5.0)
          end)

        case match do
          nil ->
            :none

          entity ->
            spline = entity[:spline] || entity["spline"]
            {:ok, normalize_spline_config(spline)}
        end

      [] ->
        :none
    end
  end

  # Check if two positions are within distance of each other
  defp position_match?({x1, y1, z1}, {x2, y2, z2}, max_dist) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    :math.sqrt(dx * dx + dy * dy + dz * dz) <= max_dist
  end

  # Normalize spline config from JSON (handles both atom and string keys)
  defp normalize_spline_config(spline) do
    %{
      spline_id: spline[:spline_id] || spline["spline_id"],
      mode: spline[:mode] || spline["mode"],
      speed: spline[:speed] || spline["speed"],
      fx: spline[:fx] || spline["fx"] || 0,
      fy: spline[:fy] || spline["fy"] || 0,
      fz: spline[:fz] || spline["fz"] || 0
    }
  end

  # Quest queries

  @doc """
  Get a quest definition by ID.
  """
  @spec get_quest(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest(id), do: get(:quests, id)

  @doc """
  Get all quests for a zone.
  Uses secondary index for O(1) lookup.
  """
  @spec get_quests_for_zone(non_neg_integer()) :: [map()]
  def get_quests_for_zone(zone_id) do
    ids = lookup_index(:quests_by_zone, zone_id)
    fetch_by_ids(:quests, ids)
  end

  @doc """
  Get all quests of a specific type.
  """
  @spec get_quests_by_type(non_neg_integer()) :: [map()]
  def get_quests_by_type(type) do
    list(:quests)
    |> Enum.filter(fn q -> q.type == type end)
  end

  @doc """
  Get a quest objective by ID.
  """
  @spec get_quest_objective(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_objective(id), do: get(:quest_objectives, id)

  @doc """
  Get quest rewards by quest ID.
  Uses secondary index for O(1) lookup.
  """
  @spec get_quest_rewards(non_neg_integer()) :: [map()]
  def get_quest_rewards(quest_id) do
    ids = lookup_index(:quest_rewards_by_quest, quest_id)
    fetch_by_ids(:quest_rewards, ids)
  end

  @doc """
  Get a quest category by ID.
  """
  @spec get_quest_category(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_category(id), do: get(:quest_categories, id)

  @doc """
  Get a quest hub by ID.
  """
  @spec get_quest_hub(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_hub(id), do: get(:quest_hubs, id)

  @doc """
  Get quest IDs that a creature can give.
  Extracts non-zero questIdGiven00-24 fields from the full creature record.
  """
  @spec get_quests_for_creature_giver(non_neg_integer()) :: [non_neg_integer()]
  def get_quests_for_creature_giver(creature_id) do
    case get_creature_full(creature_id) do
      {:ok, creature} ->
        0..24
        |> Enum.map(fn i ->
          key = String.to_atom("questIdGiven#{String.pad_leading(Integer.to_string(i), 2, "0")}")
          Map.get(creature, key)
        end)
        |> Enum.reject(&(&1 == 0 or is_nil(&1)))

      :error ->
        []
    end
  end

  @doc """
  Get quest IDs that a creature can receive turn-ins for.
  Extracts non-zero questIdReceive00-24 fields from the full creature record.
  """
  @spec get_quests_for_creature_receiver(non_neg_integer()) :: [non_neg_integer()]
  def get_quests_for_creature_receiver(creature_id) do
    case get_creature_full(creature_id) do
      {:ok, creature} ->
        0..24
        |> Enum.map(fn i ->
          key = String.to_atom("questIdReceive#{String.pad_leading(Integer.to_string(i), 2, "0")}")
          Map.get(creature, key)
        end)
        |> Enum.reject(&(&1 == 0 or is_nil(&1)))

      :error ->
        []
    end
  end

  @doc """
  Get quest definition with all objective definitions included.
  Joins the quest with its objectives based on objective0-5 fields.
  """
  @spec get_quest_with_objectives(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_with_objectives(quest_id) do
    case get(:quests, quest_id) do
      {:ok, quest} ->
        objectives =
          0..5
          |> Enum.map(fn i ->
            key = String.to_atom("objective#{i}")
            Map.get(quest, key)
          end)
          |> Enum.reject(&(&1 == 0 or is_nil(&1)))
          |> Enum.map(&get(:quest_objectives, &1))
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, obj} -> obj end)

        {:ok, Map.put(quest, :objectives, objectives)}

      :error ->
        :error
    end
  end

  @doc """
  Check if creature is a quest giver.
  """
  @spec creature_quest_giver?(non_neg_integer()) :: boolean()
  def creature_quest_giver?(creature_id) do
    get_quests_for_creature_giver(creature_id) != []
  end

  @doc """
  Check if creature is a quest receiver (turn-in NPC).
  """
  @spec creature_quest_receiver?(non_neg_integer()) :: boolean()
  def creature_quest_receiver?(creature_id) do
    get_quests_for_creature_receiver(creature_id) != []
  end

  # NPC/Vendor queries

  @doc """
  Get vendor data by vendor ID.
  """
  @spec get_vendor(non_neg_integer()) :: {:ok, map()} | :error
  def get_vendor(id), do: get(:npc_vendors, id)

  @doc """
  Get vendor by creature ID.
  Uses secondary index for O(1) lookup.
  """
  @spec get_vendor_by_creature(non_neg_integer()) :: {:ok, map()} | :error
  def get_vendor_by_creature(creature_id) do
    case lookup_index(:vendors_by_creature, creature_id) do
      [id | _] -> get(:npc_vendors, id)
      [] -> :error
    end
  end

  @doc """
  Get all vendors of a specific type.
  Uses secondary index for O(1) lookup.
  """
  @spec get_vendors_by_type(String.t()) :: [map()]
  def get_vendors_by_type(vendor_type) do
    ids = lookup_index(:vendors_by_type, vendor_type)
    fetch_by_ids(:npc_vendors, ids)
  end

  @doc """
  Get all vendors.
  """
  @spec get_all_vendors() :: [map()]
  def get_all_vendors, do: list(:npc_vendors)

  @doc """
  Get vendor inventory by vendor ID.
  """
  @spec get_vendor_inventory(non_neg_integer()) :: {:ok, map()} | :error
  def get_vendor_inventory(vendor_id), do: get(:vendor_inventories, vendor_id)

  @doc """
  Get vendor inventory items for a creature.
  Returns the list of items the vendor sells, or empty list if not a vendor.
  """
  @spec get_vendor_items_for_creature(non_neg_integer()) :: [map()]
  def get_vendor_items_for_creature(creature_id) do
    case get_vendor_by_creature(creature_id) do
      {:ok, vendor} ->
        case get_vendor_inventory(vendor.id) do
          {:ok, inventory} -> inventory.items
          :error -> []
        end

      :error ->
        []
    end
  end

  @doc """
  Get creature affiliation by ID.
  """
  @spec get_creature_affiliation(non_neg_integer()) :: {:ok, map()} | :error
  def get_creature_affiliation(id), do: get(:creature_affiliations, id)

  @doc """
  Get full creature data by ID.
  Returns complete creature2 record with all 173 fields.
  """
  @spec get_creature_full(non_neg_integer()) :: {:ok, map()} | :error
  def get_creature_full(id), do: get(:creatures_full, id)

  # Gossip/Dialogue queries

  @doc """
  Get a gossip entry by ID.
  """
  @spec get_gossip_entry(non_neg_integer()) :: {:ok, map()} | :error
  def get_gossip_entry(id), do: get(:gossip_entries, id)

  @doc """
  Get gossip entries for a gossip set.
  Uses secondary index for O(1) lookup.
  """
  @spec get_gossip_entries_for_set(non_neg_integer()) :: [map()]
  def get_gossip_entries_for_set(set_id) do
    ids = lookup_index(:gossip_entries_by_set, set_id)
    fetch_by_ids(:gossip_entries, ids)
  end

  @doc """
  Get a gossip set by ID.
  """
  @spec get_gossip_set(non_neg_integer()) :: {:ok, map()} | :error
  def get_gossip_set(id), do: get(:gossip_sets, id)

  # Achievement queries

  @doc """
  Get an achievement by ID.
  """
  @spec get_achievement(non_neg_integer()) :: {:ok, map()} | :error
  def get_achievement(id), do: get(:achievements, id)

  @doc """
  Get achievements for a category.
  Uses secondary index for O(1) lookup.
  """
  @spec get_achievements_for_category(non_neg_integer()) :: [map()]
  def get_achievements_for_category(category_id) do
    ids = lookup_index(:achievements_by_category, category_id)
    fetch_by_ids(:achievements, ids)
  end

  @doc """
  Get achievements for a zone.
  Uses secondary index for O(1) lookup.
  """
  @spec get_achievements_for_zone(non_neg_integer()) :: [map()]
  def get_achievements_for_zone(zone_id) do
    ids = lookup_index(:achievements_by_zone, zone_id)
    fetch_by_ids(:achievements, ids)
  end

  @doc """
  Get an achievement category by ID.
  """
  @spec get_achievement_category(non_neg_integer()) :: {:ok, map()} | :error
  def get_achievement_category(id), do: get(:achievement_categories, id)

  @doc """
  Get achievement checklist items for an achievement.
  """
  @spec get_achievement_checklists(non_neg_integer()) :: [map()]
  def get_achievement_checklists(achievement_id) do
    list(:achievement_checklists)
    |> Enum.filter(fn c -> c.achievementId == achievement_id end)
    |> Enum.sort_by(fn c -> c.bit end)
  end

  # Path queries

  @doc """
  Get a path mission by ID.
  """
  @spec get_path_mission(non_neg_integer()) :: {:ok, map()} | :error
  def get_path_mission(id), do: get(:path_missions, id)

  @doc """
  Get path missions for an episode.
  Uses secondary index for O(1) lookup.
  """
  @spec get_path_missions_for_episode(non_neg_integer()) :: [map()]
  def get_path_missions_for_episode(episode_id) do
    ids = lookup_index(:path_missions_by_episode, episode_id)
    fetch_by_ids(:path_missions, ids)
  end

  @doc """
  Get path missions by path type (0=Soldier, 1=Settler, 2=Scientist, 3=Explorer).
  Uses secondary index for O(1) lookup.
  """
  @spec get_path_missions_by_type(non_neg_integer()) :: [map()]
  def get_path_missions_by_type(path_type) do
    ids = lookup_index(:path_missions_by_type, path_type)
    fetch_by_ids(:path_missions, ids)
  end

  @doc """
  Get a path episode by ID.
  """
  @spec get_path_episode(non_neg_integer()) :: {:ok, map()} | :error
  def get_path_episode(id), do: get(:path_episodes, id)

  @doc """
  Get a path reward by ID.
  """
  @spec get_path_reward(non_neg_integer()) :: {:ok, map()} | :error
  def get_path_reward(id), do: get(:path_rewards, id)

  @doc """
  Get path episodes for a zone.
  Uses composite index for O(1) lookup.
  """
  @spec get_path_episodes_for_zone(non_neg_integer(), non_neg_integer()) :: [map()]
  def get_path_episodes_for_zone(world_id, zone_id) do
    ids = lookup_index(:path_episodes_by_zone, {world_id, zone_id})
    fetch_by_ids(:path_episodes, ids)
  end

  @doc """
  Get path missions for a zone and path type.
  Returns all missions available in the zone for the specified path.
  """
  @spec get_zone_path_missions(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: [map()]
  def get_zone_path_missions(world_id, zone_id, path_type) do
    get_path_episodes_for_zone(world_id, zone_id)
    |> Enum.filter(fn ep -> ep["pathTypeEnum"] == path_type end)
    |> Enum.flat_map(fn ep -> get_path_missions_for_episode(ep["ID"]) end)
  end

  # Challenge queries

  @doc """
  Get a challenge by ID.
  """
  @spec get_challenge(non_neg_integer()) :: {:ok, map()} | :error
  def get_challenge(id), do: get(:challenges, id)

  @doc """
  Get challenges for a zone.
  Uses secondary index for O(1) lookup.
  """
  @spec get_challenges_for_zone(non_neg_integer()) :: [map()]
  def get_challenges_for_zone(zone_id) do
    ids = lookup_index(:challenges_by_zone, zone_id)
    fetch_by_ids(:challenges, ids)
  end

  @doc """
  Get a challenge tier by ID.
  """
  @spec get_challenge_tier(non_neg_integer()) :: {:ok, map()} | :error
  def get_challenge_tier(id), do: get(:challenge_tiers, id)

  # World Location queries

  @doc """
  Get a world location by ID.
  """
  @spec get_world_location(non_neg_integer()) :: {:ok, map()} | :error
  def get_world_location(id), do: get(:world_locations, id)

  @doc """
  Get world locations for a world.
  Uses secondary index for O(1) lookup.
  """
  @spec get_world_locations_for_world(non_neg_integer()) :: [map()]
  def get_world_locations_for_world(world_id) do
    ids = lookup_index(:world_locations_by_world, world_id)
    fetch_by_ids(:world_locations, ids)
  end

  @doc """
  Get world locations for a zone.
  Uses secondary index for O(1) lookup.
  """
  @spec get_world_locations_for_zone(non_neg_integer()) :: [map()]
  def get_world_locations_for_zone(zone_id) do
    ids = lookup_index(:world_locations_by_zone, zone_id)
    fetch_by_ids(:world_locations, ids)
  end

  @doc """
  Get a bind point by ID.
  """
  @spec get_bind_point(non_neg_integer()) :: {:ok, map()} | :error
  def get_bind_point(id), do: get(:bind_points, id)

  # Prerequisite queries

  @doc """
  Get a prerequisite by ID.
  """
  @spec get_prerequisite(non_neg_integer()) :: {:ok, map()} | :error
  def get_prerequisite(id), do: get(:prerequisites, id)

  # Loot queries

  @doc """
  Get a loot table by ID.
  """
  @spec get_loot_table(non_neg_integer()) :: {:ok, map()} | :error
  def get_loot_table(id), do: get(:loot_tables, id)

  @doc """
  Get all loot tables.
  """
  @spec get_all_loot_tables() :: [map()]
  def get_all_loot_tables, do: list(:loot_tables)

  @doc """
  Get creature loot rules configuration.
  """
  @spec get_creature_loot_rules() :: map() | nil
  def get_creature_loot_rules do
    case :ets.lookup(table_name(:creature_loot_rules), :rules) do
      [{:rules, rules}] -> rules
      [] -> nil
    end
  end

  @doc """
  Get loot table override for a specific creature.
  """
  @spec get_creature_loot_override(non_neg_integer()) :: map() | nil
  def get_creature_loot_override(creature_id) do
    case :ets.lookup(table_name(:creature_loot_rules), {:override, creature_id}) do
      [{{:override, ^creature_id}, override}] -> override
      _ ->
        # Try alternate key format
        case :ets.match(table_name(:creature_loot_rules), {:override, creature_id, :"$1"}) do
          [[override]] -> override
          _ -> nil
        end
    end
  end

  @doc """
  Get loot category tables mapping.
  """
  @spec get_loot_category_tables() :: map() | nil
  def get_loot_category_tables do
    case :ets.lookup(table_name(:creature_loot_rules), :categories) do
      [{:categories, categories}] -> categories
      [] -> nil
    end
  end

  # Harvest node loot queries

  @doc """
  Get harvest node loot data by creature ID.

  Returns loot configuration for a harvest node including:
  - tradeskill_id: The gathering profession (13=Mining, 15=Survivalist, 18=Relic Hunter, 20=Farming)
  - tradeskill_name: Human-readable profession name
  - tier: Skill tier (1-5)
  - loot: Map with :primary and :secondary drop lists
  """
  @spec get_harvest_loot(non_neg_integer()) :: {:ok, map()} | :error
  def get_harvest_loot(creature_id), do: get(:harvest_loot, creature_id)

  @doc """
  Get all harvest loot mappings.
  """
  @spec get_all_harvest_loot() :: [map()]
  def get_all_harvest_loot, do: list(:harvest_loot)

  @doc """
  Get harvest loot by tradeskill ID.
  """
  @spec get_harvest_loot_by_tradeskill(non_neg_integer()) :: [map()]
  def get_harvest_loot_by_tradeskill(tradeskill_id) do
    list(:harvest_loot)
    |> Enum.filter(fn data ->
      Map.get(data, :tradeskill_id) == tradeskill_id
    end)
  end

  # Character Creation API

  @doc """
  Get a character creation template by ID.

  The CharacterCreation table maps CharacterCreationId to race, class, sex, faction,
  and starting items. Used during character creation to resolve the template.
  """
  @spec get_character_creation(non_neg_integer()) :: {:ok, map()} | :error
  def get_character_creation(id), do: get(:character_creations, id)

  @doc "List all character creation templates."
  @spec get_all_character_creations() :: [map()]
  def get_all_character_creations, do: list(:character_creations)

  @doc """
  Get item visuals for character customization.

  Converts a list of (label, value) pairs into ItemVisual entries (slot, displayId)
  based on the CharacterCustomization table for the given race and sex.

  This is used during character creation to generate the appearance data
  that gets stored and sent back in the character list.

  ## Parameters

  - `race` - Race ID (1=Human, 3=Granok, etc.)
  - `sex` - Sex (0=Male, 1=Female)
  - `customizations` - List of {label, value} tuples from character creation

  ## Returns

  List of `%{slot: slot_id, display_id: display_id}` maps.
  """
  @spec get_item_visuals(non_neg_integer(), non_neg_integer(), [{non_neg_integer(), non_neg_integer()}]) :: [map()]
  def get_item_visuals(race, sex, customizations) do
    # Get all customization entries for this race/sex combo
    # Race 0 entries are defaults that apply to all races
    race_entries = get_customizations_for_race_sex(race, sex)
    default_entries = get_customizations_for_race_sex(0, sex)
    all_entries = race_entries ++ default_entries

    # Convert customizations list to a map for efficient lookup
    custom_map = Map.new(customizations)

    # For each entry that matches a customization, return the slot/displayId
    # Filter entries where flags = 2 (enabled) and the label/value matches
    all_entries
    |> Enum.filter(fn entry ->
      # Entry is enabled (flags = 2)
      entry.flags == 2 &&
        # And matches at least one customization
        matches_customization?(entry, custom_map)
    end)
    |> Enum.map(fn entry ->
      %{slot: entry.itemSlotId, display_id: entry.itemDisplayId}
    end)
    |> Enum.uniq_by(fn %{slot: slot} -> slot end)
  end

  # Check if an entry matches the given customizations
  defp matches_customization?(entry, custom_map) do
    label0 = entry.characterCustomizationLabelId00
    value0 = entry.value00
    label1 = entry.characterCustomizationLabelId01
    value1 = entry.value01

    # Match if label0/value0 matches (ignoring 0 labels)
    match0 = label0 == 0 || Map.get(custom_map, label0) == value0

    # Match if label1/value1 matches (ignoring 0 labels)
    match1 = label1 == 0 || Map.get(custom_map, label1) == value1

    # Both must match (or be 0/ignored)
    match0 && match1 && (label0 != 0 || label1 != 0)
  end

  # Get customizations indexed by race/sex
  defp get_customizations_for_race_sex(race, sex) do
    case :ets.lookup(index_table_name(:customizations_by_race_sex), {race, sex}) do
      [{{^race, ^sex}, entries}] -> entries
      [] -> []
    end
  end

  @doc """
  Get the equipment slot for an item.

  Uses the item's type_id to look up the slot from Item2Type table.

  ## Parameters

  - `item_id` - The item ID

  ## Returns

  The ItemSlot ID (e.g., 1=ArmorChest, 20=WeaponPrimary) or nil if not found.
  """
  @spec get_item_slot(non_neg_integer()) :: non_neg_integer() | nil
  def get_item_slot(item_id) do
    with {:ok, item} <- get(:items, item_id),
         type_id when type_id > 0 <- get_item_type_id(item),
         {:ok, item_type} <- get(:item_types, type_id) do
      # item_type has itemSlotId field
      get_slot_id(item_type)
    else
      _ -> nil
    end
  end

  defp get_item_type_id(item) do
    Map.get(item, "type_id") || Map.get(item, :type_id) || 0
  end

  defp get_slot_id(item_type) do
    Map.get(item_type, "itemSlotId") || Map.get(item_type, :itemSlotId) || 0
  end

  @doc """
  Get default gear visuals for a character class.

  Uses CharacterCreationArmorSet to get display IDs for starting gear.
  Returns visuals for the Arkship creation type (gear set 0).

  ## Parameters

  - `class_id` - The class ID (1=Warrior, 2=Esper, etc.)

  ## Returns

  List of `%{slot: slot_id, display_id: display_id}` maps.
  """
  @spec get_class_gear_visuals(non_neg_integer()) :: [map()]
  def get_class_gear_visuals(class_id) do
    # Find armor set for this class with creationGearSetEnum = 0 (Arkship)
    armor_sets = list(:creation_armor_sets)

    armor_set =
      Enum.find(armor_sets, fn set ->
        set_class = Map.get(set, "classId") || Map.get(set, :classId) || 0
        gear_set = Map.get(set, "creationGearSetEnum") || Map.get(set, :creationGearSetEnum) || 0
        set_class == class_id && gear_set == 0
      end)

    if armor_set do
      # Map display IDs to slots
      # ItemDisplayId00 = WeaponPrimary (slot 20)
      # ItemDisplayId01 = ArmorChest (slot 1)
      # ItemDisplayId02 = ArmorLegs (slot 2)
      # ItemDisplayId03 = ArmorHead (slot 3)
      # ItemDisplayId04 = ArmorShoulder (slot 4)
      # ItemDisplayId05 = ArmorFeet (slot 5)
      # ItemDisplayId06 = ArmorHands (slot 6)
      slot_mapping = [
        {"itemDisplayId00", 20},  # WeaponPrimary
        {"itemDisplayId01", 1},   # ArmorChest
        {"itemDisplayId02", 2},   # ArmorLegs
        {"itemDisplayId03", 3},   # ArmorHead
        {"itemDisplayId04", 4},   # ArmorShoulder
        {"itemDisplayId05", 5},   # ArmorFeet
        {"itemDisplayId06", 6}    # ArmorHands
      ]

      slot_mapping
      |> Enum.map(fn {key, slot} ->
        display_id = Map.get(armor_set, key) || Map.get(armor_set, String.to_atom(key)) || 0
        if display_id > 0, do: %{slot: slot, display_id: display_id}, else: nil
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  @doc """
  Get the display ID for an item, resolving through ItemDisplaySource if needed.

  Items with `item_source_id > 0` use the ItemDisplaySourceEntry table to
  look up level-scaled visuals. Items with `item_source_id = 0` use their
  direct `display_id` field.

  ## Parameters

  - `item_id` - The item ID
  - `power_level` - Optional power level for level-based lookups (defaults to item's power_level)

  ## Returns

  The display ID for the item, or 0 if not found.

  ## Example

      # Item with direct display_id
      Store.get_item_display_id(81344) #=> 4160

      # Item with item_source_id (level-scaled)
      Store.get_item_display_id(28366, 50) #=> varies by level
  """
  @spec get_item_display_id(non_neg_integer(), non_neg_integer() | nil) :: non_neg_integer()
  def get_item_display_id(item_id, power_level \\ nil) do
    case get(:items, item_id) do
      {:ok, item} ->
        item_source_id = get_item_field(item, :item_source_id) || 0
        display_id = get_item_field(item, :display_id) || 0
        item_power_level = power_level || get_item_field(item, :power_level) || 0
        type_id = get_item_field(item, :type_id) || 0

        if item_source_id > 0 do
          # Look up from ItemDisplaySourceEntry by source_id and level
          resolve_display_from_source(item_source_id, type_id, item_power_level, display_id)
        else
          # Use direct display_id
          display_id
        end

      :error ->
        0
    end
  end

  # Resolve display_id from ItemDisplaySourceEntry table
  defp resolve_display_from_source(source_id, type_id, power_level, fallback_display_id) do
    # Get all entries for this source_id
    entries = get_display_source_entries(source_id)

    # Filter by type_id
    matching_entries = Enum.filter(entries, fn entry ->
      entry_type_id = Map.get(entry, :Item2TypeId) || Map.get(entry, "Item2TypeId") || 0
      entry_type_id == type_id
    end)

    case matching_entries do
      [] ->
        # No entries, use fallback
        fallback_display_id

      [single] ->
        # Single entry, use its display_id
        Map.get(single, :ItemDisplayId) || Map.get(single, "ItemDisplayId") || fallback_display_id

      multiple when is_list(multiple) ->
        # Multiple entries - check if we have an explicit display_id first
        if fallback_display_id > 0 do
          fallback_display_id
        else
          # Find entry matching level range
          level_match = Enum.find(multiple, fn entry ->
            min_level = Map.get(entry, :ItemMinLevel) || Map.get(entry, "ItemMinLevel") || 0
            max_level = Map.get(entry, :ItemMaxLevel) || Map.get(entry, "ItemMaxLevel") || 999
            power_level >= min_level and power_level <= max_level
          end)

          if level_match do
            Map.get(level_match, :ItemDisplayId) || Map.get(level_match, "ItemDisplayId") || fallback_display_id
          else
            fallback_display_id
          end
        end
    end
  end

  # Get display source entries for a source_id (uses index)
  defp get_display_source_entries(source_id) do
    case :ets.lookup(index_table_name(:display_sources_by_source_id), source_id) do
      [{^source_id, entries}] -> entries
      [] -> []
    end
  end

  # Helper to get item field with both atom and string key support
  defp get_item_field(item, field) when is_atom(field) do
    Map.get(item, field) || Map.get(item, Atom.to_string(field))
  end

  @doc """
  Get the 3D model path for an item by item ID.

  Resolves the display ID (handling level-scaled items) and looks up the
  model path from the ItemDisplay table.

  ## Parameters

  - `item_id` - The item ID
  - `power_level` - Optional power level for level-based lookups (defaults to item's power_level)

  ## Returns

  A map with model information, or nil if not found:
  - `:model_path` - Path to the .m3 model file (uses objectModelL or skinnedModelL)
  - `:display_id` - The resolved display ID
  - `:description` - Model description from ItemDisplay

  ## Example

      Store.get_item_model_path(1)
      #=> %{model_path: "Art\\Item\\Armor\\Light\\...", display_id: 3954, description: "AMR_D_Light_012_Chest"}

      Store.get_item_model_path(999999) #=> nil
  """
  @spec get_item_model_path(non_neg_integer(), non_neg_integer() | nil) :: map() | nil
  def get_item_model_path(item_id, power_level \\ nil) do
    display_id = get_item_display_id(item_id, power_level)

    if display_id > 0 do
      get_display_model_path(display_id)
    else
      nil
    end
  end

  @doc """
  Get the 3D model path for a display ID directly.

  Looks up the model path from the ItemDisplay table by display ID.

  ## Parameters

  - `display_id` - The ItemDisplay ID

  ## Returns

  A map with model information, or nil if not found:
  - `:model_path` - Path to the .m3 model file
  - `:display_id` - The display ID
  - `:description` - Model description

  ## Example

      Store.get_display_model_path(3954)
      #=> %{model_path: "Art\\Item\\Armor\\Light\\...", display_id: 3954, description: "..."}
  """
  @spec get_display_model_path(non_neg_integer()) :: map() | nil
  def get_display_model_path(display_id) when is_integer(display_id) and display_id > 0 do
    case :ets.lookup(table_name(:item_displays), display_id) do
      [{^display_id, display}] ->
        # Prefer objectModelL (world model), fall back to skinnedModelL (equipped model)
        model_path =
          get_display_field(display, :objectModelL) ||
            get_display_field(display, :skinnedModelL) ||
            get_display_field(display, :objectModel) ||
            get_display_field(display, :skinnedModel) ||
            ""

        if model_path != "" do
          %{
            model_path: model_path,
            display_id: display_id,
            description: get_display_field(display, :description) || ""
          }
        else
          nil
        end

      [] ->
        nil
    end
  end

  def get_display_model_path(_), do: nil

  # Helper to get display field with both atom and string key support
  defp get_display_field(display, field) when is_atom(field) do
    value = Map.get(display, field) || Map.get(display, Atom.to_string(field))
    if value == "", do: nil, else: value
  end

  @doc """
  Get localized text by ID.

  ## Returns

  The localized text string, or nil if not found.

  ## Examples

      Store.get_text(2680) #=> "Some Item Name"
      Store.get_text(0) #=> nil
  """
  @spec get_text(non_neg_integer()) :: String.t() | nil
  def get_text(text_id) when is_integer(text_id) and text_id > 0 do
    case :ets.lookup(table_name(:texts), text_id) do
      [{^text_id, text}] when is_binary(text) -> text
      _ -> nil
    end
  end

  def get_text(_), do: nil

  @doc """
  Search items by ID or name.

  Searches items by:
  - Exact item ID (if query is numeric)
  - Partial name match (case-insensitive)

  Results include the localized item name for display.

  ## Options

    * `:limit` - Maximum number of results (default: 50)

  ## Returns

  List of item maps with an additional `:name` field containing the localized name.

  ## Examples

      # Search by ID
      Store.search_items("12345") #=> [%{id: 12345, name: "Sword of Power", ...}]

      # Search by name
      Store.search_items("sword") #=> [%{id: 100, name: "Iron Sword", ...}, ...]
  """
  @spec search_items(String.t(), keyword()) :: [map()]
  def search_items(query, opts \\ [])

  def search_items(query, opts) when is_binary(query) do
    query = String.trim(query)
    limit = Keyword.get(opts, :limit, 50)

    cond do
      query == "" ->
        []

      # Check if query is a number (item ID)
      numeric?(query) ->
        case Integer.parse(query) do
          {id, ""} ->
            case get(:items, id) do
              {:ok, item} -> [add_item_name(item)]
              :error -> []
            end

          _ ->
            []
        end

      # Search by name
      true ->
        search_items_by_name(query, limit)
    end
  end

  def search_items(_, _), do: []

  defp numeric?(str) do
    case Integer.parse(str) do
      {_, ""} -> true
      _ -> false
    end
  end

  defp search_items_by_name(query, limit) do
    query_lower = String.downcase(query)

    # Build a list of {item, name} for items that have names
    table_name(:items)
    |> :ets.tab2list()
    |> Stream.map(fn {_id, item} -> {item, get_item_name(item)} end)
    |> Stream.filter(fn {_item, name} -> name != nil end)
    |> Stream.filter(fn {_item, name} ->
      String.contains?(String.downcase(name), query_lower)
    end)
    |> Stream.map(fn {item, name} -> Map.put(item, :name, name) end)
    |> Enum.take(limit)
  end

  @doc """
  Get an item by ID with its localized name.

  Returns {:ok, item_with_name} or :error if item not found.

  ## Example

      {:ok, item} = Store.get_item_with_name(12345)
      item.name #=> "Iron Sword"
  """
  @spec get_item_with_name(non_neg_integer()) :: {:ok, map()} | :error
  def get_item_with_name(item_id) do
    case get(:items, item_id) do
      {:ok, item} -> {:ok, add_item_name(item)}
      :error -> :error
    end
  end

  defp add_item_name(item) do
    name = get_item_name(item)
    item_id = Map.get(item, :ID) || Map.get(item, :id, 0)
    Map.put(item, :name, name || "Item ##{item_id}")
  end

  defp get_item_name(item) do
    # Check both naming conventions: our internal name and the raw JSON field name
    text_id =
      get_item_field(item, :name_text_id) ||
        Map.get(item, :localizedTextIdName) ||
        0

    if text_id > 0 do
      get_text(text_id)
    else
      nil
    end
  end

  @doc """
  Resolve loot table for a creature based on rules.

  Returns the loot table ID and modifiers for a creature based on:
  1. Direct override (if creature has a specific loot table assigned)
  2. Rule-based resolution using race_id, tier_id, and difficulty_id

  Returns {:ok, %{loot_table_id, gold_multiplier, drop_bonus}} or :error
  """
  @spec resolve_creature_loot(non_neg_integer()) :: {:ok, map()} | :error
  def resolve_creature_loot(creature_id) do
    # Check for direct override first
    case get_creature_loot_override(creature_id) do
      nil ->
        # Use rule-based resolution
        resolve_loot_by_rules(creature_id)

      override ->
        {:ok,
         %{
           loot_table_id: override.loot_table_id,
           gold_multiplier: Map.get(override, :gold_multiplier, 1.0),
           drop_bonus: Map.get(override, :drop_bonus, 0)
         }}
    end
  end

  defp resolve_loot_by_rules(creature_id) do
    rules = get_creature_loot_rules()

    if rules do
      # Get creature data
      case get(:creatures, creature_id) do
        {:ok, creature} ->
          race_id = creature.race_id
          tier_id = creature.tier_id
          difficulty_id = creature.difficulty_id

          race_mappings = get_rule_map(rules, :race_mappings)
          tier_modifiers = get_rule_map(rules, :tier_modifiers)
          difficulty_modifiers = get_rule_map(rules, :difficulty_modifiers)

          # Get race mapping (try integer key, string key, then default)
          race_mapping = get_rule_value(race_mappings, race_id, %{base_table: 1})

          base_table = get_map_value(race_mapping, :base_table, 1)

          # Get tier modifier
          tier_mod = get_rule_value(tier_modifiers, tier_id, %{})

          # Get difficulty modifier
          diff_mod = get_rule_value(difficulty_modifiers, difficulty_id, %{})

          # Calculate final values
          table_offset = get_map_value(tier_mod, :table_offset, 0)
          final_table = base_table + table_offset

          tier_gold_mult = get_map_value(tier_mod, :gold_multiplier, 1.0)
          diff_gold_mult = get_map_value(diff_mod, :gold_multiplier, 1.0)
          final_gold_mult = tier_gold_mult * diff_gold_mult

          tier_drop_bonus = get_map_value(tier_mod, :drop_bonus, 0)
          diff_drop_bonus = get_map_value(diff_mod, :drop_bonus, 0)
          final_drop_bonus = tier_drop_bonus + diff_drop_bonus

          {:ok,
           %{
             loot_table_id: final_table,
             gold_multiplier: final_gold_mult,
             drop_bonus: final_drop_bonus,
             extra_table: get_map_value(tier_mod, :extra_table, nil)
           }}

        :error ->
          # Creature not found, use default
          {:ok, %{loot_table_id: 1, gold_multiplier: 1.0, drop_bonus: 0}}
      end
    else
      # No rules loaded, use default
      {:ok, %{loot_table_id: 1, gold_multiplier: 1.0, drop_bonus: 0}}
    end
  end

  # Helper to get rule map, handling both atom and string keys
  defp get_rule_map(rules, key) when is_atom(key) do
    Map.get(rules, key) || Map.get(rules, Atom.to_string(key), %{})
  end

  # Helper to get value from rule map, trying integer, string, atom keys, then default
  defp get_rule_value(rule_map, key, default) when is_integer(key) do
    str_key = Integer.to_string(key)

    Map.get(rule_map, key) ||
      Map.get(rule_map, str_key) ||
      Map.get(rule_map, String.to_atom(str_key)) ||
      Map.get(rule_map, :default) ||
      Map.get(rule_map, "default", default)
  end

  # Helper to get value from map, handling both atom and string keys
  defp get_map_value(map, key, default) when is_atom(key) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key), default)
      value -> value
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    for table <- @tables do
      :ets.new(table_name(table), [:set, :public, :named_table, read_concurrency: true])
    end

    # Create secondary index tables
    for table <- @index_tables do
      :ets.new(index_table_name(table), [:set, :public, :named_table, read_concurrency: true])
    end

    # Load data
    load_all_data()

    {:ok, %{}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    load_all_data()
    {:reply, :ok, state}
  end

  # Private functions

  defp table_name(table), do: :"bezgelor_data_#{table}"
  defp index_table_name(table), do: :"bezgelor_index_#{table}"

  defp load_all_data do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("Loading game data...")

    # Compile all data files if needed
    compile_start = System.monotonic_time(:millisecond)

    case Compiler.compile_all() do
      :ok -> Logger.debug("Data compilation complete")
      {:error, reason} -> Logger.warning("Compilation issue: #{inspect(reason)}")
    end

    compile_time = System.monotonic_time(:millisecond) - compile_start
    Logger.info("Compile check: #{compile_time}ms")

    # Load creatures first (creatures_full depends on it)
    creatures_start = System.monotonic_time(:millisecond)
    load_table(:creatures, "creatures.json", "creatures")
    load_creatures_full()
    creatures_time = System.monotonic_time(:millisecond) - creatures_start
    Logger.info("Loaded creatures in #{creatures_time}ms")

    # Load all other tables
    tables_start = System.monotonic_time(:millisecond)

    table_loaders = [
      # Core data
      fn -> load_table(:zones, "zones.json", "zones") end,
      fn -> load_spells_split() end,
      fn -> load_items_split() end,
      fn -> load_client_table(:item_types, "Item2Type.json", "item2type") end,
      fn -> load_client_table(:creation_armor_sets, "CharacterCreationArmorSet.json", "charactercreationarmorset") end,
      fn -> load_table(:texts, "texts.json", "texts") end,
      fn -> load_table(:house_types, "house_types.json", "house_types") end,
      fn -> load_table(:housing_decor, "housing_decor.json", "decor") end,
      fn -> load_table(:housing_fabkits, "housing_fabkits.json", "fabkits") end,
      fn -> load_table(:titles, "titles.json", "titles") end,
      # Tradeskill data
      fn -> load_table(:tradeskill_professions, "tradeskill_professions.json", "professions") end,
      fn -> load_table(:tradeskill_schematics, "tradeskill_schematics.json", "schematics") end,
      fn -> load_table(:tradeskill_talents, "tradeskill_talents.json", "talents") end,
      fn -> load_table(:tradeskill_additives, "tradeskill_additives.json", "additives") end,
      fn -> load_table(:tradeskill_nodes, "tradeskill_nodes.json", "node_types") end,
      fn -> load_table(:tradeskill_work_orders, "tradeskill_work_orders.json", "work_order_templates") end,
      # Public events data
      fn -> load_table(:public_events, "public_events.json", "public_events") end,
      fn -> load_table(:world_bosses, "world_bosses.json", "world_bosses") end,
      fn -> load_table_by_zone(:event_spawn_points, "event_spawn_points.json", "event_spawn_points") end,
      fn -> load_table(:event_loot_tables, "event_loot_tables.json", "event_loot_tables") end,
      # Instance/dungeon data
      fn -> load_table(:instances, "instances.json", "instances") end,
      fn -> load_table(:instance_bosses, "instance_bosses.json", "instance_bosses") end,
      fn -> load_mythic_affixes() end,
      # PvP data
      fn -> load_battlegrounds() end,
      fn -> load_arenas() end,
      fn -> load_warplot_plugs() end,
      # Spawn data
      fn -> load_creature_spawns() end,
      # Quest data
      fn -> load_client_table(:quests, "quests.json", "quest2") end,
      fn -> load_client_table(:quest_objectives, "quest_objectives.json", "questobjective") end,
      fn -> load_client_table_with_fk(:quest_rewards, "quest_rewards.json", "quest2reward", :quest2Id) end,
      fn -> load_client_table(:quest_categories, "quest_categories.json", "questcategory") end,
      fn -> load_client_table(:quest_hubs, "quest_hubs.json", "questhub") end,
      # NPC/Vendor data
      fn -> load_table(:npc_vendors, "npc_vendors.json", "npc_vendors") end,
      fn -> load_vendor_inventories() end,
      fn -> load_client_table(:creature_affiliations, "creature_affiliations.json", "creature2affiliation") end,
      # Dialogue data
      fn -> load_client_table(:gossip_entries, "gossip_entries.json", "gossipentry") end,
      fn -> load_client_table(:gossip_sets, "gossip_sets.json", "gossipset") end,
      # Achievement data
      fn -> load_client_table(:achievements, "achievements.json", "achievement") end,
      fn -> load_client_table(:achievement_categories, "achievement_categories.json", "achievementcategory") end,
      fn -> load_client_table(:achievement_checklists, "achievement_checklists.json", "achievementchecklist") end,
      # Path data
      fn -> load_client_table(:path_missions, "path_missions.json", "pathmission") end,
      fn -> load_client_table(:path_episodes, "path_episodes.json", "pathepisode") end,
      fn -> load_client_table(:path_rewards, "path_rewards.json", "pathreward") end,
      # Challenge data
      fn -> load_client_table(:challenges, "challenges.json", "challenge") end,
      fn -> load_client_table(:challenge_tiers, "challenge_tiers.json", "challengetier") end,
      # World location data
      fn -> load_client_table(:world_locations, "world_locations.json", "worldlocation2") end,
      fn -> load_client_table(:bind_points, "bind_points.json", "bindpoint") end,
      # Prerequisites
      fn -> load_client_table(:prerequisites, "prerequisites.json", "prerequisite") end,
      # Loot data
      fn -> load_loot_tables() end,
      fn -> load_creature_loot_rules() end,
      # Harvest node loot
      fn -> load_harvest_loot() end,
      # Character creation templates
      fn -> load_client_table(:character_creations, "CharacterCreation.json", "charactercreation") end,
      # Character customization
      fn -> load_character_customizations() end,
      # Item display source entries
      fn -> load_item_display_sources() end,
      # Item display data (model paths)
      fn -> load_item_displays() end,
      # Patrol paths
      fn -> load_patrol_paths() end,
      # Spline data
      fn -> load_splines() end,
      # Entity spline mappings (from NexusForever database)
      fn -> load_entity_splines() end
    ]

    Enum.each(table_loaders, fn loader -> loader.() end)

    tables_time = System.monotonic_time(:millisecond) - tables_start
    Logger.info("Loaded #{length(table_loaders)} tables in #{tables_time}ms")

    # Validate loot data (requires loot tables loaded)
    validate_start = System.monotonic_time(:millisecond)
    validate_loot_data()
    validate_time = System.monotonic_time(:millisecond) - validate_start
    Logger.info("Loot validation: #{validate_time}ms")

    # Build secondary indexes
    # This MUST happen before enrichment because get_spline_nodes uses the spline_nodes_by_spline index
    index_start = System.monotonic_time(:millisecond)
    build_all_indexes()
    index_time = System.monotonic_time(:millisecond) - index_start
    Logger.info("Built indexes in #{index_time}ms")

    # Enrich creature spawns with pre-computed spline data
    # This must happen AFTER indexes are built because get_spline_nodes requires spline_nodes_by_spline index
    enrich_start = System.monotonic_time(:millisecond)
    enrich_creature_spawns_with_splines()
    enrich_time = System.monotonic_time(:millisecond) - enrich_start
    Logger.info("Spawn enrichment: #{enrich_time}ms")

    # Build achievement event index for O(1) lookup
    ach_start = System.monotonic_time(:millisecond)
    BezgelorData.AchievementIndex.build_index()
    ach_time = System.monotonic_time(:millisecond) - ach_start
    Logger.info("Achievement index: #{ach_time}ms")

    total_time = System.monotonic_time(:millisecond) - start_time
    Logger.info("Game data loaded in #{total_time}ms: #{inspect(stats())}")
  end

  defp load_table(table, json_file, key) do
    table_name = table_name(table)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    case Compiler.load_data(json_file, key) do
      {:ok, items} when is_list(items) ->
        # Bulk insert is much faster than individual inserts
        tuples = Enum.map(items, fn item -> {item.id, item} end)
        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(items)} #{key}")

      {:ok, items} when is_map(items) ->
        # Texts table is a map of id -> string - bulk convert and insert
        tuples =
          Enum.map(items, fn {id, text} ->
            int_id =
              cond do
                is_integer(id) -> id
                is_binary(id) -> String.to_integer(id)
                is_atom(id) -> id |> Atom.to_string() |> String.to_integer()
              end

            {int_id, text}
          end)

        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{map_size(items)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key}: #{inspect(reason)}")
    end
  end

  defp load_table_by_zone(table, json_file, key) do
    table_name = table_name(table)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    case Compiler.load_data(json_file, key) do
      {:ok, items} when is_list(items) ->
        # Bulk insert indexed by zone_id
        tuples = Enum.map(items, fn item -> {item.zone_id, item} end)
        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(items)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key}: #{inspect(reason)}")
    end
  end

  # Load tables from WildStar client data (uses uppercase ID field)
  defp load_client_table(table, json_file, key) do
    table_name = table_name(table)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), json_file)

    case load_json_raw(json_path) do
      {:ok, data} ->
        items = Map.get(data, String.to_atom(key), [])

        # Bulk insert with ID normalization
        tuples =
          items
          |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
          |> Enum.map(fn item ->
            id = Map.get(item, :ID)
            normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
            {id, normalized}
          end)

        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(tuples)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key} from #{json_file}: #{inspect(reason)}")
    end
  end

  # Load client table that needs a foreign key index (e.g., quest_rewards by quest_id)
  defp load_client_table_with_fk(table, json_file, key, _fk_field) do
    table_name = table_name(table)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), json_file)

    case load_json_raw(json_path) do
      {:ok, data} ->
        items = Map.get(data, String.to_atom(key), [])

        # Bulk insert with ID normalization
        tuples =
          items
          |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
          |> Enum.map(fn item ->
            id = Map.get(item, :ID)
            normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
            {id, normalized}
          end)

        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(tuples)} #{key}")

      {:error, reason} ->
        Logger.warning("Failed to load #{key} from #{json_file}: #{inspect(reason)}")
    end
  end

  defp load_vendor_inventories do
    table_name = table_name(:vendor_inventories)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "vendor_inventories.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        inventories = Map.get(data, :vendor_inventories, [])

        # Bulk insert indexed by vendor_id
        tuples = Enum.map(inventories, fn inv -> {inv.vendor_id, inv} end)
        :ets.insert(table_name, tuples)

        total_items = Enum.reduce(inventories, 0, fn inv, acc -> acc + length(inv.items) end)
        Logger.debug("Loaded #{length(inventories)} vendor inventories (#{total_items} total items)")

      {:error, reason} ->
        Logger.warning("Failed to load vendor inventories: #{inspect(reason)}")
    end
  end

  defp load_mythic_affixes do
    table_name = table_name(:mythic_affixes)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "mythic_affixes.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load individual affixes
        affixes = Map.get(data, :mythic_affixes, [])

        for affix <- affixes do
          :ets.insert(table_name, {affix.id, affix})
        end

        # Store weekly rotation as metadata
        if rotation_data = Map.get(data, :weekly_rotation) do
          rotations = Map.get(rotation_data, :rotations, [])
          :ets.insert(table_name, {:weekly_rotation, rotations})
        end

        Logger.debug("Loaded #{length(affixes)} mythic affixes")

      {:error, reason} ->
        Logger.warning("Failed to load mythic affixes: #{inspect(reason)}")
    end
  end

  # Load JSON with ETF caching for faster subsequent loads
  defp load_json_raw(path) do
    etf_path = etf_cache_path(path)

    # Try loading from ETF cache first
    case load_etf_cache(path, etf_path) do
      {:ok, data} ->
        {:ok, data}

      :stale ->
        # Parse JSON and cache to ETF
        with {:ok, content} <- File.read(path),
             {:ok, data} <- Jason.decode(content, keys: :atoms) do
          cache_to_etf(etf_path, data)
          {:ok, data}
        end
    end
  end

  # Get the compiled/cached ETF directory path
  defp compiled_directory do
    Application.app_dir(:bezgelor_data, "priv/compiled")
  end

  # Generate ETF cache path for a JSON file
  defp etf_cache_path(json_path) do
    compiled_dir = compiled_directory()
    basename = Path.basename(json_path, ".json") <> ".etf"
    Path.join(compiled_dir, basename)
  end

  # Load from ETF cache if fresh, returns :stale if cache is missing or outdated
  defp load_etf_cache(json_path, etf_path) do
    with {:ok, json_stat} <- File.stat(json_path),
         {:ok, etf_stat} <- File.stat(etf_path),
         true <- etf_stat.mtime >= json_stat.mtime,
         {:ok, content} <- File.read(etf_path) do
      try do
        {:ok, :erlang.binary_to_term(content)}
      rescue
        _ -> :stale
      end
    else
      _ -> :stale
    end
  end

  # Cache parsed data to ETF file
  defp cache_to_etf(etf_path, data) do
    compiled_dir = Path.dirname(etf_path)
    File.mkdir_p!(compiled_dir)
    etf_content = :erlang.term_to_binary(data, [:compressed])
    File.write(etf_path, etf_content)
  rescue
    _ -> :ok  # Silently ignore cache write failures
  end

  defp load_battlegrounds do
    table_name = table_name(:battlegrounds)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "battlegrounds.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load regular battlegrounds
        battlegrounds = Map.get(data, :battlegrounds, [])

        for bg <- battlegrounds do
          :ets.insert(table_name, {bg.id, bg})
        end

        # Load rated battlegrounds (with offset IDs starting at 100)
        rated_bgs = Map.get(data, :rated_battlegrounds, [])

        for rbg <- rated_bgs do
          :ets.insert(table_name, {rbg.id, rbg})
        end

        Logger.debug("Loaded #{length(battlegrounds) + length(rated_bgs)} battlegrounds")

      {:error, reason} ->
        Logger.warning("Failed to load battlegrounds: #{inspect(reason)}")
    end
  end

  defp load_arenas do
    table_name = table_name(:arenas)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "arenas.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load arena definitions
        arenas = Map.get(data, :arenas, [])

        for arena <- arenas do
          :ets.insert(table_name, {arena.id, arena})
        end

        # Store bracket configuration as metadata
        if brackets = Map.get(data, :brackets) do
          :ets.insert(table_name, {:brackets, brackets})
        end

        # Store rating rewards as metadata
        if rating_rewards = Map.get(data, :rating_rewards) do
          :ets.insert(table_name, {:rating_rewards, rating_rewards})
        end

        Logger.debug("Loaded #{length(arenas)} arenas")

      {:error, reason} ->
        Logger.warning("Failed to load arenas: #{inspect(reason)}")
    end
  end

  defp load_warplot_plugs do
    table_name = table_name(:warplot_plugs)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "warplot_plugs.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load plug definitions
        plugs = Map.get(data, :plugs, [])

        for plug <- plugs do
          :ets.insert(table_name, {plug.id, plug})
        end

        # Store categories as metadata
        if categories = Map.get(data, :categories) do
          :ets.insert(table_name, {:categories, categories})
        end

        # Store socket layout as metadata
        if socket_layout = Map.get(data, :socket_layout) do
          :ets.insert(table_name, {:socket_layout, socket_layout})
        end

        # Store warplot settings as metadata
        if warplot_settings = Map.get(data, :warplot_settings) do
          :ets.insert(table_name, {:warplot_settings, warplot_settings})
        end

        Logger.debug("Loaded #{length(plugs)} warplot plugs")

      {:error, reason} ->
        Logger.warning("Failed to load warplot plugs: #{inspect(reason)}")
    end
  end

  defp load_creatures_full do
    table_name = table_name(:creatures_full)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    # Load from split part files (each under 100MB for GitHub) - in parallel
    part_files = [
      "creatures_part1.json",
      "creatures_part2.json",
      "creatures_part3.json",
      "creatures_part4.json"
    ]

    # Load all parts in parallel, then insert
    results =
      part_files
      |> Task.async_stream(
        fn filename ->
          json_path = Path.join(data_directory(), filename)

          case load_json_raw(json_path) do
            {:ok, data} ->
              creatures = Map.get(data, :creature2, [])
              tuples = Enum.map(creatures, fn creature -> {Map.get(creature, :ID), creature} end)
              {:ok, tuples}

            {:error, reason} ->
              Logger.warning("Failed to load #{filename}: #{inspect(reason)}")
              {:ok, []}
          end
        end,
        max_concurrency: 4,
        timeout: 60_000
      )
      |> Enum.reduce([], fn {:ok, {:ok, tuples}}, acc -> acc ++ tuples end)

    # Bulk insert all at once
    :ets.insert(table_name, results)

    Logger.debug("Loaded #{length(results)} full creature records from #{length(part_files)} parts (parallel)")
  end

  defp load_items_split do
    table_name = table_name(:items)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    # Load from split part files (each under 100MB for GitHub) - in parallel
    part_files = [
      "items_part1.json",
      "items_part2.json",
      "items_part3.json",
      "items_part4.json"
    ]

    # Load all parts in parallel, then insert
    results =
      part_files
      |> Task.async_stream(
        fn filename ->
          json_path = Path.join(data_directory(), filename)

          case load_json_raw(json_path) do
            {:ok, data} ->
              items = Map.get(data, :item2, [])
              tuples = Enum.map(items, fn item -> {Map.get(item, :ID), item} end)
              {:ok, tuples}

            {:error, reason} ->
              Logger.warning("Failed to load #{filename}: #{inspect(reason)}")
              {:ok, []}
          end
        end,
        max_concurrency: 4,
        timeout: 60_000
      )
      |> Enum.reduce([], fn {:ok, {:ok, tuples}}, acc -> acc ++ tuples end)

    # Bulk insert all at once
    :ets.insert(table_name, results)

    Logger.debug("Loaded #{length(results)} items from #{length(part_files)} parts (parallel)")
  end

  defp load_spells_split do
    table_name = table_name(:spells)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    # Load from split part files (each under 100MB for GitHub) - in parallel
    part_files = [
      "spells_part1.json",
      "spells_part2.json",
      "spells_part3.json",
      "spells_part4.json"
    ]

    # Load all parts in parallel, then insert
    results =
      part_files
      |> Task.async_stream(
        fn filename ->
          json_path = Path.join(data_directory(), filename)

          case load_json_raw(json_path) do
            {:ok, data} ->
              spells = Map.get(data, :spell4, [])
              tuples = Enum.map(spells, fn spell -> {Map.get(spell, :ID), spell} end)
              {:ok, tuples}

            {:error, reason} ->
              Logger.warning("Failed to load #{filename}: #{inspect(reason)}")
              {:ok, []}
          end
        end,
        max_concurrency: 4,
        timeout: 60_000
      )
      |> Enum.reduce([], fn {:ok, {:ok, tuples}}, acc -> acc ++ tuples end)

    # Bulk insert all at once
    :ets.insert(table_name, results)

    Logger.debug("Loaded #{length(results)} spells from #{length(part_files)} parts (parallel)")
  end

  defp load_loot_tables do
    table_name = table_name(:loot_tables)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "loot_tables.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        tables = Map.get(data, :loot_tables, [])
        # Bulk insert
        tuples = Enum.map(tables, fn table -> {table.id, table} end)
        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(tables)} loot tables")

      {:error, reason} ->
        Logger.warning("Failed to load loot tables: #{inspect(reason)}")
    end
  end

  defp load_creature_loot_rules do
    table_name = table_name(:creature_loot_rules)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "creature_loot.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Store the rules configuration
        if rules = Map.get(data, :creature_loot_rules) do
          :ets.insert(table_name, {:rules, rules})
        end

        # Store creature overrides
        if overrides = Map.get(data, :creature_overrides) do
          override_list = Map.get(overrides, :overrides, [])

          for override <- override_list do
            :ets.insert(table_name, {:override, override.creature_id, override})
          end

          :ets.insert(table_name, {:override_count, length(override_list)})
        end

        # Store category tables
        if categories = Map.get(data, :category_tables) do
          :ets.insert(table_name, {:categories, categories})
        end

        Logger.debug("Loaded creature loot rules")

      {:error, reason} ->
        Logger.warning("Failed to load creature loot rules: #{inspect(reason)}")
    end
  end

  defp load_harvest_loot do
    table_name = table_name(:harvest_loot)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "harvest_loot.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Data is a map of creature_id (string) -> loot info
        count =
          Enum.reduce(data, 0, fn {key, loot_data}, acc ->
            # Convert string key to integer
            creature_id =
              cond do
                is_integer(key) -> key
                is_binary(key) -> String.to_integer(key)
                is_atom(key) -> key |> Atom.to_string() |> String.to_integer()
              end

            :ets.insert(table_name, {creature_id, loot_data})
            acc + 1
          end)

        Logger.debug("Loaded #{count} harvest node loot mappings")

      {:error, reason} ->
        Logger.warning("Failed to load harvest loot: #{inspect(reason)}")
    end
  end

  defp load_character_customizations do
    table_name = table_name(:character_customizations)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "CharacterCustomization.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        items = Map.get(data, :charactercustomization, [])

        # Bulk insert with ID normalization
        tuples =
          items
          |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
          |> Enum.map(fn item ->
            id = Map.get(item, :ID)
            normalized = Map.put(item, :id, id)
            {id, normalized}
          end)

        :ets.insert(table_name, tuples)

        # Build the race/sex index
        build_customizations_index(items)

        Logger.debug("Loaded #{length(tuples)} character customizations")

      {:error, reason} ->
        Logger.warning("Failed to load character customizations: #{inspect(reason)}")
    end
  end

  # Build the customizations_by_race_sex index for efficient lookup
  defp build_customizations_index(items) do
    index_name = index_table_name(:customizations_by_race_sex)

    # Clear existing index
    :ets.delete_all_objects(index_name)

    # Group by {raceId, gender} and bulk insert
    tuples =
      items
      |> Enum.group_by(fn item ->
        {Map.get(item, :raceId, 0), Map.get(item, :gender, 0)}
      end)
      |> Enum.map(fn {{race, sex}, entries} -> {{race, sex}, entries} end)

    :ets.insert(index_name, tuples)
  end

  # Load ItemDisplaySourceEntry data for level-scaled item visuals
  # File structure: { "itemdisplaysourceentry": [ {ID, ItemSourceId, Item2TypeId, ItemMinLevel, ItemMaxLevel, ItemDisplayId, Icon}, ...] }
  defp load_item_display_sources do
    table_name = table_name(:item_display_sources)
    index_name = index_table_name(:display_sources_by_source_id)

    # Clear existing data
    :ets.delete_all_objects(table_name)
    :ets.delete_all_objects(index_name)

    json_path = Path.join(data_directory(), "ItemDisplaySourceEntry.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        items = Map.get(data, :itemdisplaysourceentry, [])

        # Bulk insert with ID normalization
        tuples =
          items
          |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
          |> Enum.map(fn item ->
            id = Map.get(item, :ID)
            normalized = Map.put(item, :id, id)
            {id, normalized}
          end)

        :ets.insert(table_name, tuples)

        # Build the source_id index for efficient lookup
        build_display_source_index(items)

        Logger.debug("Loaded #{length(tuples)} item display source entries")

      {:error, _reason} ->
        # ItemDisplaySourceEntry.json is optional - many items don't use it
        Logger.debug("ItemDisplaySourceEntry.json not found (optional - items will use direct display_id)")
    end
  end

  # Build the display_sources_by_source_id index for efficient lookup
  defp build_display_source_index(items) do
    index_name = index_table_name(:display_sources_by_source_id)

    # Group by ItemSourceId and bulk insert
    tuples =
      items
      |> Enum.group_by(fn item ->
        Map.get(item, :ItemSourceId) || Map.get(item, "ItemSourceId") || 0
      end)
      |> Enum.filter(fn {source_id, _} -> source_id > 0 end)
      |> Enum.map(fn {source_id, entries} -> {source_id, entries} end)

    :ets.insert(index_name, tuples)
  end

  # Load ItemDisplay data for model paths and textures
  # File structure: { "itemdisplay": [ {ID, description, objectModel, skinnedModel, ...}, ...] }
  defp load_item_displays do
    table_name = table_name(:item_displays)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "ItemDisplay.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        items = Map.get(data, :itemdisplay, [])

        # Bulk insert with ID normalization
        tuples =
          items
          |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
          |> Enum.map(fn item ->
            id = Map.get(item, :ID)
            normalized = Map.put(item, :id, id)
            {id, normalized}
          end)

        :ets.insert(table_name, tuples)
        Logger.debug("Loaded #{length(tuples)} item displays")

      {:error, _reason} ->
        Logger.debug("ItemDisplay.json not found (optional - 3D models unavailable)")
    end
  end

  defp validate_loot_data do
    alias BezgelorData.LootValidator

    case LootValidator.validate_all() do
      {:ok, stats} ->
        Logger.debug(
          "Loot data validated: #{stats.tables.table_count} tables, " <>
            "#{stats.tables.entry_count} entries, #{stats.rules.race_mappings} race mappings"
        )

      {:error, errors} ->
        for error <- errors do
          Logger.warning("Loot validation error: #{error}")
        end
    end
  end

  defp load_creature_spawns do
    table_name = table_name(:creature_spawns)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    # Try loading from pre-enriched ETF cache first
    enriched_etf_path = Path.join(compiled_directory(), "creature_spawns_enriched.etf")
    Logger.info("Creature spawns: checking ETF at #{enriched_etf_path}, exists? #{File.exists?(enriched_etf_path)}")
    is_fresh = enriched_etf_cache_fresh?(enriched_etf_path)
    Logger.info("Creature spawns: enriched ETF fresh? #{is_fresh}")

    if is_fresh do
      result = load_creature_spawns_from_etf(enriched_etf_path, table_name)
      Logger.info("Loaded creature spawns from enriched ETF cache: #{result}")
      result
    else
      Logger.info("Enriched ETF not fresh, loading from JSON and will re-enrich")
      load_creature_spawns_from_json(table_name)
    end
  end

  # Check if enriched ETF cache is newer than all source files
  # Must check ALL files that contribute to enriched data:
  # - creature_spawns.json (spawn positions)
  # - harvest_spawns.json (resource spawns)
  # - entity_splines.json (creature->spline mappings)
  # - Spline2.json (spline definitions)
  # - Spline2Node.json (spline waypoints)
  defp enriched_etf_cache_fresh?(etf_path) do
    data_dir = data_directory()
    Logger.debug("Checking enriched ETF cache freshness")
    Logger.debug("  ETF path: #{etf_path}")
    Logger.debug("  Data dir: #{data_dir}")

    json_path = Path.join(data_dir, "creature_spawns.json")
    harvest_path = Path.join(data_dir, "harvest_spawns.json")
    entity_splines_path = Path.join(data_dir, "entity_splines.json")
    spline2_path = Path.join(data_dir, "Spline2.json")
    spline2_nodes_path = Path.join(data_dir, "Spline2Node.json")

    result = with {:ok, etf_stat} <- File.stat(etf_path),
         {:ok, json_stat} <- File.stat(json_path),
         true <- etf_stat.mtime >= json_stat.mtime,
         # Check all optional source files
         true <- file_not_newer?(harvest_path, etf_stat.mtime),
         true <- file_not_newer?(entity_splines_path, etf_stat.mtime),
         true <- file_not_newer?(spline2_path, etf_stat.mtime),
         true <- file_not_newer?(spline2_nodes_path, etf_stat.mtime) do
      true
    else
      {:error, :enoent} ->
        Logger.debug("Enriched ETF cache check: file not found (#{etf_path})")
        false
      {:error, reason} ->
        Logger.debug("Enriched ETF cache check failed: #{inspect(reason)}")
        false
      false ->
        Logger.debug("Enriched ETF cache check: source file newer than ETF")
        false
      other ->
        Logger.debug("Enriched ETF cache check failed: #{inspect(other)}")
        false
    end

    Logger.debug("Enriched ETF cache fresh? #{result}")
    result
  end

  # Returns true if file doesn't exist or is not newer than reference mtime
  defp file_not_newer?(path, reference_mtime) do
    case File.stat(path) do
      {:ok, stat} -> stat.mtime <= reference_mtime
      {:error, :enoent} -> true
      _ -> false
    end
  end

  # Load pre-enriched creature spawns directly from ETF cache
  defp load_creature_spawns_from_etf(etf_path, table_name) do
    case File.read(etf_path) do
      {:ok, content} ->
        try do
          zone_data_list = :erlang.binary_to_term(content)

          for {world_id, zone_data} <- zone_data_list do
            :ets.insert(table_name, {world_id, zone_data})
          end

          total_creatures =
            Enum.reduce(zone_data_list, 0, fn {_wid, z}, acc -> acc + length(z.creature_spawns) end)

          total_resources =
            Enum.reduce(zone_data_list, 0, fn {_wid, z}, acc -> acc + length(z.resource_spawns) end)

          total_objects =
            Enum.reduce(zone_data_list, 0, fn {_wid, z}, acc -> acc + length(z.object_spawns) end)

          # Count enriched spawns for debugging
          total_enriched =
            Enum.reduce(zone_data_list, 0, fn {_wid, z}, acc ->
              acc + Enum.count(z.creature_spawns, &Map.has_key?(&1, :patrol_waypoints))
            end)

          Logger.info(
            "Loaded #{length(zone_data_list)} zones from enriched cache " <>
            "(#{total_creatures} creatures, #{total_enriched} enriched with patrol, #{total_resources} resources, #{total_objects} objects)"
          )

          :from_cache
        rescue
          e ->
            Logger.warning("Failed to parse enriched ETF cache: #{inspect(e)}, loading from JSON")
            load_creature_spawns_from_json(table_name)
        end

      {:error, reason} ->
        Logger.warning("Failed to read enriched ETF cache: #{inspect(reason)}, loading from JSON")
        load_creature_spawns_from_json(table_name)
    end
  end

  # Load creature spawns from JSON (non-enriched)
  defp load_creature_spawns_from_json(table_name) do
    json_path = Path.join(data_directory(), "creature_spawns.json")

    # Also load harvest spawns from separate file
    harvest_path = Path.join(data_directory(), "harvest_spawns.json")
    harvest_by_world = load_harvest_spawns(harvest_path)

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load zone spawn data, keyed by world_id
        zone_spawns = Map.get(data, :zone_spawns, [])

        for zone_data <- zone_spawns do
          world_id = zone_data.world_id

          # Merge harvest spawns into resource_spawns
          harvest_spawns = Map.get(harvest_by_world, world_id, [])
          merged_zone_data = Map.put(zone_data, :resource_spawns, harvest_spawns)

          :ets.insert(table_name, {world_id, merged_zone_data})
        end

        total_creatures =
          Enum.reduce(zone_spawns, 0, fn z, acc -> acc + length(z.creature_spawns) end)

        total_resources =
          Enum.reduce(zone_spawns, 0, fn z, acc ->
            acc + length(Map.get(harvest_by_world, z.world_id, []))
          end)

        total_objects =
          Enum.reduce(zone_spawns, 0, fn z, acc -> acc + length(z.object_spawns) end)

        Logger.debug(
          "Loaded #{length(zone_spawns)} zone spawn data (#{total_creatures} creatures, #{total_resources} resources, #{total_objects} objects)"
        )

        :from_json

      {:error, reason} ->
        Logger.warning("Failed to load creature spawns: #{inspect(reason)}")
        :error
    end
  end

  # Enrich creature spawns with pre-computed spline data from entity_splines
  # This runs once at data load time, not per-creature at spawn time
  # Results are cached to ETF for fast subsequent loads
  defp enrich_creature_spawns_with_splines do
    enriched_etf_path = Path.join(compiled_directory(), "creature_spawns_enriched.etf")

    # Skip if ETF cache is fresh (data was already loaded enriched)
    is_fresh = enriched_etf_cache_fresh?(enriched_etf_path)
    Logger.info("Spawn enrichment: ETF fresh? #{is_fresh}")

    if is_fresh do
      Logger.info("Spawn enrichment: skipping (using cached data)")
      :skipped
    else
      Logger.info("Spawn enrichment: running enrichment process")
      do_enrich_creature_spawns_with_splines(enriched_etf_path)
    end
  end

  defp do_enrich_creature_spawns_with_splines(etf_path) do
    creature_table = table_name(:creature_spawns)
    spline_table = table_name(:entity_splines)

    # Get all zone spawn data
    zones = :ets.tab2list(creature_table)

    enriched_zones =
      Enum.map(zones, fn {world_id, zone_data} ->
        # Get entity_splines for this world
        entity_splines =
          case :ets.lookup(spline_table, world_id) do
            [{^world_id, entities}] -> entities
            [] -> []
          end

        if entity_splines == [] do
          {world_id, zone_data, 0}
        else
          # Build a lookup map for faster matching: {creature_id, position} -> spline_config
          spline_lookup = build_spline_lookup(entity_splines)

          # Enrich each creature spawn with spline data if it matches
          {enriched_spawns, count} =
            Enum.map_reduce(zone_data.creature_spawns, 0, fn spawn, acc ->
              [x, y, z] = spawn.position
              pos = {x, y, z}

              case find_matching_spline(spline_lookup, spawn.creature_id, pos) do
                nil ->
                  {spawn, acc}

                spline_config ->
                  # Pre-fetch the actual patrol waypoints
                  enriched =
                    case get_spline_as_patrol(spline_config.spline_id) do
                      {:ok, patrol_data} ->
                        Map.merge(spawn, %{
                          spline_config: spline_config,
                          patrol_waypoints: patrol_data.waypoints,
                          patrol_speed: if(spline_config.speed < 0, do: 3.0, else: spline_config.speed),
                          patrol_mode: spline_mode_to_atom(spline_config.mode)
                        })

                      :error ->
                        spawn
                    end

                  {enriched, acc + 1}
              end
            end)

          updated_zone = %{zone_data | creature_spawns: enriched_spawns}
          {world_id, updated_zone, count}
        end
      end)

    # Update ETS with enriched data
    total_enriched =
      Enum.reduce(enriched_zones, 0, fn {world_id, zone_data, count}, acc ->
        :ets.insert(creature_table, {world_id, zone_data})
        acc + count
      end)

    # Save enriched data to ETF cache for fast subsequent loads
    save_enriched_spawns_to_etf(etf_path, enriched_zones)

    Logger.info("Enriched #{total_enriched} creature spawns with patrol paths (cached)")
  end

  # Save enriched creature spawn data to ETF cache
  defp save_enriched_spawns_to_etf(etf_path, enriched_zones) do
    # Convert to list of {world_id, zone_data} tuples (without count)
    zone_data_list =
      Enum.map(enriched_zones, fn {world_id, zone_data, _count} ->
        {world_id, zone_data}
      end)

    # Ensure compiled directory exists
    compiled_dir = Path.dirname(etf_path)
    File.mkdir_p!(compiled_dir)

    # Write compressed ETF
    etf_content = :erlang.term_to_binary(zone_data_list, [:compressed])
    File.write!(etf_path, etf_content)
  rescue
    error ->
      Logger.warning("Failed to save enriched spawn cache: #{inspect(error)}")
  end

  # Build a lookup structure for efficient spline matching
  defp build_spline_lookup(entity_splines) do
    Enum.reduce(entity_splines, %{}, fn entity, acc ->
      creature_id = entity[:creature_id] || entity["creature_id"]
      position = entity[:position] || entity["position"]
      spline = entity[:spline] || entity["spline"]

      {x, y, z} =
        case position do
          [px, py, pz] -> {px, py, pz}
          {px, py, pz} -> {px, py, pz}
          _ -> {0, 0, 0}
        end

      # Use rounded position as key for faster lookup
      key = {creature_id, round(x), round(y), round(z)}
      Map.put(acc, key, {position, normalize_spline_config(spline)})
    end)
  end

  # Find matching spline using lookup map
  defp find_matching_spline(lookup, creature_id, {px, py, pz}) do
    # Try exact rounded position first
    key = {creature_id, round(px), round(py), round(pz)}

    case Map.get(lookup, key) do
      {_pos, spline_config} ->
        spline_config

      nil ->
        # Fall back to nearby positions (within 5 units)
        find_nearby_spline(lookup, creature_id, {px, py, pz}, 5.0)
    end
  end

  defp find_nearby_spline(lookup, creature_id, {px, py, pz}, tolerance) do
    # Search nearby rounded positions
    Enum.find_value(-1..1, fn dx ->
      Enum.find_value(-1..1, fn dy ->
        Enum.find_value(-1..1, fn dz ->
          key = {creature_id, round(px) + dx, round(py) + dy, round(pz) + dz}

          case Map.get(lookup, key) do
            {[ex, ey, ez], spline_config} ->
              dist = :math.sqrt((px - ex) ** 2 + (py - ey) ** 2 + (pz - ez) ** 2)
              if dist <= tolerance, do: spline_config, else: nil

            _ ->
              nil
          end
        end)
      end)
    end)
  end

  # Convert spline mode integer to atom (duplicated from CreatureManager for data loading)
  defp spline_mode_to_atom(0), do: :one_shot
  defp spline_mode_to_atom(1), do: :back_and_forth
  defp spline_mode_to_atom(2), do: :cyclic
  defp spline_mode_to_atom(3), do: :one_shot_reverse
  defp spline_mode_to_atom(4), do: :back_and_forth_reverse
  defp spline_mode_to_atom(5), do: :cyclic_reverse
  defp spline_mode_to_atom(8), do: :cyclic
  defp spline_mode_to_atom(_), do: :cyclic

  # Load harvest spawns from separate file and merge by world_id
  defp load_harvest_spawns(path) do
    case load_json_raw(path) do
      {:ok, data} ->
        zone_spawns = Map.get(data, :zone_spawns, [])

        # Multiple zones can have the same world_id, so merge their spawns
        Enum.reduce(zone_spawns, %{}, fn zone_data, acc ->
          world_id = zone_data.world_id
          spawns = Map.get(zone_data, :harvest_spawns, [])
          existing = Map.get(acc, world_id, [])
          Map.put(acc, world_id, existing ++ spawns)
        end)

      {:error, _reason} ->
        %{}
    end
  end

  # Load patrol paths for creature movement (uses string keys like "entrance_patrol_1")
  defp load_patrol_paths do
    table_name = table_name(:patrol_paths)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "patrol_paths.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        patrol_paths = Map.get(data, :patrol_paths, %{})

        for {path_name, path_data} <- patrol_paths do
          # Convert atom key to string if needed
          name_str =
            if is_atom(path_name), do: Atom.to_string(path_name), else: path_name

          # Convert waypoint positions from lists to tuples for Vector3 compatibility
          waypoints =
            Enum.map(path_data.waypoints, fn wp ->
              [x, y, z] = wp.position
              %{position: {x, y, z}, pause_ms: wp.pause_ms}
            end)

          # Store with normalized data
          normalized = %{
            name: name_str,
            display_name: Map.get(path_data, :name, name_str),
            instance_id: Map.get(path_data, :instance_id),
            waypoints: waypoints,
            mode: String.to_atom(path_data.mode),
            speed: path_data.speed
          }

          :ets.insert(table_name, {name_str, normalized})
        end

        Logger.debug("Loaded #{map_size(patrol_paths)} patrol paths")

      {:error, reason} ->
        Logger.warning("Failed to load patrol paths: #{inspect(reason)}")
    end
  end

  # Load splines from client-extracted data (Spline2.tbl and Spline2Node.tbl)
  defp load_splines do
    splines_table = table_name(:splines)
    nodes_table = table_name(:spline_nodes)

    # Clear existing data
    :ets.delete_all_objects(splines_table)
    :ets.delete_all_objects(nodes_table)

    # Load Spline2 (spline definitions)
    splines_path = Path.join(data_directory(), "Spline2.json")

    spline_count =
      case load_json_raw(splines_path) do
        {:ok, data} ->
          splines = Map.get(data, :spline2, [])

          for spline <- splines do
            normalized = %{
              id: spline[:ID],
              world_id: spline[:worldId],
              spline_type: spline[:splineType]
            }

            :ets.insert(splines_table, {spline[:ID], normalized})
          end

          length(splines)

        {:error, _reason} ->
          0
      end

    # Load Spline2Node (spline waypoints) - split across multiple files
    node_count =
      1..4
      |> Enum.map(fn part ->
        nodes_path = Path.join(data_directory(), "Spline2Node_part#{part}.json")

        case load_json_raw(nodes_path) do
          {:ok, data} ->
            nodes = Map.get(data, :spline2node, [])

            for node <- nodes do
              normalized = %{
                id: node[:ID],
                spline_id: node[:splineId],
                ordinal: node[:ordinal],
                position0: node[:position0],
                position1: node[:position1],
                position2: node[:position2],
                facing0: node[:facing0],
                facing1: node[:facing1],
                facing2: node[:facing2],
                facing3: node[:facing3],
                delay: node[:delay],
                frame_time: node[:frameTime]
              }

              :ets.insert(nodes_table, {node[:ID], normalized})
            end

            length(nodes)

          {:error, _reason} ->
            0
        end
      end)
      |> Enum.sum()

    if spline_count > 0 do
      Logger.debug("Loaded #{spline_count} splines with #{node_count} waypoints")
    end
  end

  # Load entity spline mappings from NexusForever.WorldDatabase
  # This tells us which creatures should follow which patrol paths
  defp load_entity_splines do
    table_name = table_name(:entity_splines)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "entity_splines.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        by_world = Map.get(data, :by_world, %{})

        # Store keyed by world_id (integer) for efficient lookup
        # JSON keys become atoms like :"1387" with keys: :atoms, so convert to integer
        for {world_id_key, entities} <- by_world do
          world_id =
            cond do
              is_integer(world_id_key) -> world_id_key
              is_binary(world_id_key) -> String.to_integer(world_id_key)
              is_atom(world_id_key) -> world_id_key |> Atom.to_string() |> String.to_integer()
            end

          :ets.insert(table_name, {world_id, entities})
        end

        total = Map.get(data, :total_count, 0)
        worlds = map_size(by_world)
        Logger.info("Loaded #{total} entity spline mappings across #{worlds} worlds")

      {:error, reason} ->
        Logger.warning("No entity spline data found: #{inspect(reason)}")
    end
  end

  # Secondary index building

  # Build all secondary indexes
  defp build_all_indexes do
    Logger.debug("Building secondary indexes...")

    # Clear all index tables EXCEPT customizations_by_race_sex
    # (which is built during load_character_customizations)
    for table <- @index_tables, table != :customizations_by_race_sex do
      :ets.delete_all_objects(index_table_name(table))
    end

    # All index builds are independent - run them in parallel
    index_builders = [
      # Profession-based indexes
      fn -> build_index(:tradeskill_schematics, :schematics_by_profession, :profession_id) end,
      fn -> build_index(:tradeskill_talents, :talents_by_profession, :profession_id) end,
      fn -> build_index(:tradeskill_nodes, :nodes_by_profession, :profession_id) end,
      fn -> build_index(:tradeskill_work_orders, :work_orders_by_profession, :profession_id) end,
      # Zone-based indexes
      fn -> build_index(:public_events, :events_by_zone, :zone_id) end,
      fn -> build_index(:world_bosses, :world_bosses_by_zone, :zone_id) end,
      # Instance indexes
      fn -> build_index_string(:instances, :instances_by_type, :type) end,
      fn -> build_index(:instance_bosses, :bosses_by_instance, :instance_id) end,
      # Quest indexes
      fn -> build_index(:quests, :quests_by_zone, :worldZoneId) end,
      fn -> build_index(:quest_rewards, :quest_rewards_by_quest, :quest2Id) end,
      # Vendor indexes
      fn -> build_index(:npc_vendors, :vendors_by_creature, :creature_id) end,
      fn -> build_index_string(:npc_vendors, :vendors_by_type, :vendor_type) end,
      # Gossip indexes
      fn -> build_index(:gossip_entries, :gossip_entries_by_set, :gossipSetId) end,
      # Achievement indexes
      fn -> build_index(:achievements, :achievements_by_category, :achievementCategoryId) end,
      fn -> build_index(:achievements, :achievements_by_zone, :worldZoneId) end,
      # Path indexes
      fn -> build_index(:path_missions, :path_missions_by_episode, :pathEpisodeId) end,
      fn -> build_index(:path_missions, :path_missions_by_type, :pathTypeEnum) end,
      fn -> build_composite_index(:path_episodes, :path_episodes_by_zone, [:worldId, :worldZoneId]) end,
      # Challenge indexes
      fn -> build_index(:challenges, :challenges_by_zone, :worldZoneId) end,
      # World location indexes
      fn -> build_index(:world_locations, :world_locations_by_world, :worldId) end,
      fn -> build_index(:world_locations, :world_locations_by_zone, :worldZoneId) end,
      # Spline node index
      fn -> build_index(:spline_nodes, :spline_nodes_by_spline, :spline_id) end
    ]

    Enum.each(index_builders, fn builder -> builder.() end)

    Logger.debug("Built #{length(index_builders)} secondary indexes")
  end

  # Build an index from a source table to an index table using an integer key field
  defp build_index(source_table, index_table, key_field) do
    source_name = table_name(source_table)
    index_name = index_table_name(index_table)

    # Group items by the key field and bulk insert
    tuples =
      :ets.tab2list(source_name)
      |> Enum.group_by(fn {_id, data} -> Map.get(data, key_field) end, fn {id, _data} -> id end)
      |> Enum.filter(fn {key, _ids} -> not is_nil(key) end)
      |> Enum.map(fn {key, ids} -> {key, ids} end)

    :ets.insert(index_name, tuples)
  end

  # Build an index using a string key field (converted to atom for storage)
  defp build_index_string(source_table, index_table, key_field) do
    source_name = table_name(source_table)
    index_name = index_table_name(index_table)

    # Group items by the key field (string keys) and bulk insert
    tuples =
      :ets.tab2list(source_name)
      |> Enum.group_by(fn {_id, data} -> Map.get(data, key_field) end, fn {id, _data} -> id end)
      |> Enum.filter(fn {key, _ids} -> not is_nil(key) end)
      |> Enum.map(fn {key, ids} -> {key, ids} end)

    :ets.insert(index_name, tuples)
  end

  # Build a composite index using multiple key fields as a tuple key
  defp build_composite_index(source_table, index_table, key_fields) do
    source_name = table_name(source_table)
    index_name = index_table_name(index_table)

    # Group items by a tuple of the key field values and bulk insert
    tuples =
      :ets.tab2list(source_name)
      |> Enum.group_by(
        fn {_id, data} ->
          Enum.map(key_fields, &Map.get(data, &1)) |> List.to_tuple()
        end,
        fn {id, _data} -> id end
      )
      |> Enum.filter(fn {key, _ids} -> not Enum.any?(Tuple.to_list(key), &is_nil/1) end)
      |> Enum.map(fn {key, ids} -> {key, ids} end)

    :ets.insert(index_name, tuples)
  end

  # Lookup IDs from an index, returns empty list if key not found
  defp lookup_index(index_table, key) do
    case :ets.lookup(index_table_name(index_table), key) do
      [{^key, ids}] -> ids
      [] -> []
    end
  end

  # Fetch full records from a table for a list of IDs
  defp fetch_by_ids(table, ids) do
    table_name = table_name(table)

    ids
    |> Enum.map(fn id ->
      case :ets.lookup(table_name, id) do
        [{^id, data}] -> data
        [] -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp data_directory do
    Application.app_dir(:bezgelor_data, "priv/data")
  end

  defp stats do
    for table <- @tables, into: %{} do
      {table, count(table)}
    end
  end
end
