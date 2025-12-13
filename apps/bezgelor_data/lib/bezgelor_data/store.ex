defmodule BezgelorData.Store do
  @moduledoc """
  ETS-backed storage for game data.

  Each data type gets its own ETS table for fast concurrent reads.
  Data is loaded at application startup from ETF files (compiled from JSON).
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
    :harvest_loot
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
    :world_locations_by_zone
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
    Logger.info("Loading game data...")

    # Compile all data files if needed
    case Compiler.compile_all() do
      :ok -> Logger.debug("Data compilation complete")
      {:error, reason} -> Logger.warning("Compilation issue: #{inspect(reason)}")
    end

    # Load each table
    load_table(:creatures, "creatures.json", "creatures")
    load_creatures_full()
    load_table(:zones, "zones.json", "zones")
    load_table(:spells, "spells.json", "spells")
    load_table(:items, "items.json", "items")
    load_table(:texts, "texts.json", "texts")
    load_table(:house_types, "house_types.json", "house_types")
    load_table(:housing_decor, "housing_decor.json", "decor")
    load_table(:housing_fabkits, "housing_fabkits.json", "fabkits")
    load_table(:titles, "titles.json", "titles")

    # Tradeskill data
    load_table(:tradeskill_professions, "tradeskill_professions.json", "professions")
    load_table(:tradeskill_schematics, "tradeskill_schematics.json", "schematics")
    load_table(:tradeskill_talents, "tradeskill_talents.json", "talents")
    load_table(:tradeskill_additives, "tradeskill_additives.json", "additives")
    load_table(:tradeskill_nodes, "tradeskill_nodes.json", "node_types")
    load_table(:tradeskill_work_orders, "tradeskill_work_orders.json", "work_order_templates")

    # Public events data
    load_table(:public_events, "public_events.json", "public_events")
    load_table(:world_bosses, "world_bosses.json", "world_bosses")
    load_table_by_zone(:event_spawn_points, "event_spawn_points.json", "event_spawn_points")
    load_table(:event_loot_tables, "event_loot_tables.json", "event_loot_tables")

    # Instance/dungeon data
    load_table(:instances, "instances.json", "instances")
    load_table(:instance_bosses, "instance_bosses.json", "instance_bosses")
    load_mythic_affixes()

    # PvP data
    load_battlegrounds()
    load_arenas()
    load_warplot_plugs()

    # Spawn data
    load_creature_spawns()

    # Quest data (extracted from client - uses uppercase ID)
    load_client_table(:quests, "quests.json", "quest2")
    load_client_table(:quest_objectives, "quest_objectives.json", "questobjective")
    load_client_table_with_fk(:quest_rewards, "quest_rewards.json", "quest2reward", :quest2Id)
    load_client_table(:quest_categories, "quest_categories.json", "questcategory")
    load_client_table(:quest_hubs, "quest_hubs.json", "questhub")

    # NPC/Vendor data
    load_table(:npc_vendors, "npc_vendors.json", "npc_vendors")
    load_vendor_inventories()
    load_client_table(:creature_affiliations, "creature_affiliations.json", "creature2affiliation")

    # Dialogue data
    load_client_table(:gossip_entries, "gossip_entries.json", "gossipentry")
    load_client_table(:gossip_sets, "gossip_sets.json", "gossipset")

    # Achievement data
    load_client_table(:achievements, "achievements.json", "achievement")
    load_client_table(:achievement_categories, "achievement_categories.json", "achievementcategory")
    load_client_table(:achievement_checklists, "achievement_checklists.json", "achievementchecklist")

    # Path data
    load_client_table(:path_missions, "path_missions.json", "pathmission")
    load_client_table(:path_episodes, "path_episodes.json", "pathepisode")
    load_client_table(:path_rewards, "path_rewards.json", "pathreward")

    # Challenge data
    load_client_table(:challenges, "challenges.json", "challenge")
    load_client_table(:challenge_tiers, "challenge_tiers.json", "challengetier")

    # World location data
    load_client_table(:world_locations, "world_locations.json", "worldlocation2")
    load_client_table(:bind_points, "bind_points.json", "bindpoint")

    # Prerequisites
    load_client_table(:prerequisites, "prerequisites.json", "prerequisite")

    # Loot data
    load_loot_tables()
    load_creature_loot_rules()

    # Harvest node loot
    load_harvest_loot()

    # Validate loot data
    validate_loot_data()

    # Build secondary indexes
    build_all_indexes()

    # Build achievement event index for O(1) lookup
    BezgelorData.AchievementIndex.build_index()

    Logger.info("Game data loaded: #{inspect(stats())}")
  end

  defp load_table(table, json_file, key) do
    table_name = table_name(table)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    case Compiler.load_data(json_file, key) do
      {:ok, items} when is_list(items) ->
        # Regular tables have lists of maps with :id
        for item <- items do
          :ets.insert(table_name, {item.id, item})
        end

        Logger.debug("Loaded #{length(items)} #{key}")

      {:ok, items} when is_map(items) ->
        # Texts table is a map of id -> string
        # Keys may be atoms (from :keys => :atoms) or strings
        for {id, text} <- items do
          int_id =
            cond do
              is_integer(id) -> id
              is_binary(id) -> String.to_integer(id)
              is_atom(id) -> id |> Atom.to_string() |> String.to_integer()
            end

          :ets.insert(table_name, {int_id, text})
        end

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
        # Items are indexed by zone_id
        for item <- items do
          :ets.insert(table_name, {item.zone_id, item})
        end

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

        for item <- items do
          # Client data uses uppercase ID
          id = Map.get(item, :ID)

          if id do
            # Normalize to lowercase :id for consistency
            normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
            :ets.insert(table_name, {id, normalized})
          end
        end

        Logger.debug("Loaded #{length(items)} #{key}")

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

        for item <- items do
          # Client data uses uppercase ID
          id = Map.get(item, :ID)

          if id do
            # Normalize to lowercase :id for consistency
            normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
            :ets.insert(table_name, {id, normalized})
          end
        end

        Logger.debug("Loaded #{length(items)} #{key}")

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

        for inv <- inventories do
          # Index by vendor_id
          :ets.insert(table_name, {inv.vendor_id, inv})
        end

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

  defp load_json_raw(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content, keys: :atoms) do
      {:ok, data}
    end
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

    # Load from split part files (each under 100MB for GitHub)
    part_files = [
      "creatures_part1.json",
      "creatures_part2.json",
      "creatures_part3.json",
      "creatures_part4.json"
    ]

    total_loaded =
      Enum.reduce(part_files, 0, fn filename, acc ->
        json_path = Path.join(data_directory(), filename)

        case load_json_raw(json_path) do
          {:ok, data} ->
            creatures = Map.get(data, :creature2, [])

            for creature <- creatures do
              id = Map.get(creature, :ID)
              :ets.insert(table_name, {id, creature})
            end

            acc + length(creatures)

          {:error, reason} ->
            Logger.warning("Failed to load #{filename}: #{inspect(reason)}")
            acc
        end
      end)

    Logger.debug("Loaded #{total_loaded} full creature records from #{length(part_files)} parts")
  end

  defp load_loot_tables do
    table_name = table_name(:loot_tables)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "loot_tables.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        tables = Map.get(data, :loot_tables, [])

        for table <- tables do
          :ets.insert(table_name, {table.id, table})
        end

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

    json_path = Path.join(data_directory(), "creature_spawns.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        # Load zone spawn data, keyed by world_id
        zone_spawns = Map.get(data, :zone_spawns, [])

        for zone_data <- zone_spawns do
          world_id = zone_data.world_id
          :ets.insert(table_name, {world_id, zone_data})
        end

        total_creatures =
          Enum.reduce(zone_spawns, 0, fn z, acc -> acc + length(z.creature_spawns) end)

        total_resources =
          Enum.reduce(zone_spawns, 0, fn z, acc -> acc + length(z.resource_spawns) end)

        total_objects =
          Enum.reduce(zone_spawns, 0, fn z, acc -> acc + length(z.object_spawns) end)

        Logger.debug(
          "Loaded #{length(zone_spawns)} zone spawn data (#{total_creatures} creatures, #{total_resources} resources, #{total_objects} objects)"
        )

      {:error, reason} ->
        Logger.warning("Failed to load creature spawns: #{inspect(reason)}")
    end
  end

  # Secondary index building

  defp build_all_indexes do
    Logger.debug("Building secondary indexes...")

    # Clear all index tables
    for table <- @index_tables do
      :ets.delete_all_objects(index_table_name(table))
    end

    # Build profession-based indexes
    build_index(:tradeskill_schematics, :schematics_by_profession, :profession_id)
    build_index(:tradeskill_talents, :talents_by_profession, :profession_id)
    build_index(:tradeskill_nodes, :nodes_by_profession, :profession_id)
    build_index(:tradeskill_work_orders, :work_orders_by_profession, :profession_id)

    # Build zone-based indexes
    build_index(:public_events, :events_by_zone, :zone_id)
    build_index(:world_bosses, :world_bosses_by_zone, :zone_id)

    # Build instance indexes
    build_index_string(:instances, :instances_by_type, :type)
    build_index(:instance_bosses, :bosses_by_instance, :instance_id)

    # Build quest indexes
    build_index(:quests, :quests_by_zone, :worldZoneId)
    build_index(:quest_rewards, :quest_rewards_by_quest, :quest2Id)

    # Build vendor indexes
    build_index(:npc_vendors, :vendors_by_creature, :creature_id)
    build_index_string(:npc_vendors, :vendors_by_type, :vendor_type)

    # Build gossip indexes
    build_index(:gossip_entries, :gossip_entries_by_set, :gossipSetId)

    # Build achievement indexes
    build_index(:achievements, :achievements_by_category, :achievementCategoryId)
    build_index(:achievements, :achievements_by_zone, :worldZoneId)

    # Build path indexes
    build_index(:path_missions, :path_missions_by_episode, :pathEpisodeId)
    build_index(:path_missions, :path_missions_by_type, :pathTypeEnum)
    build_composite_index(:path_episodes, :path_episodes_by_zone, [:worldId, :worldZoneId])

    # Build challenge indexes
    build_index(:challenges, :challenges_by_zone, :worldZoneId)

    # Build world location indexes
    build_index(:world_locations, :world_locations_by_world, :worldId)
    build_index(:world_locations, :world_locations_by_zone, :worldZoneId)

    Logger.debug("Secondary indexes built")
  end

  # Build an index from a source table to an index table using an integer key field
  defp build_index(source_table, index_table, key_field) do
    source_name = table_name(source_table)
    index_name = index_table_name(index_table)

    # Group items by the key field
    groups =
      :ets.tab2list(source_name)
      |> Enum.group_by(fn {_id, data} -> Map.get(data, key_field) end, fn {id, _data} -> id end)

    # Insert each group into the index table
    for {key, ids} <- groups, not is_nil(key) do
      :ets.insert(index_name, {key, ids})
    end
  end

  # Build an index using a string key field (converted to atom for storage)
  defp build_index_string(source_table, index_table, key_field) do
    source_name = table_name(source_table)
    index_name = index_table_name(index_table)

    # Group items by the key field (string keys)
    groups =
      :ets.tab2list(source_name)
      |> Enum.group_by(fn {_id, data} -> Map.get(data, key_field) end, fn {id, _data} -> id end)

    # Insert each group into the index table
    for {key, ids} <- groups, not is_nil(key) do
      :ets.insert(index_name, {key, ids})
    end
  end

  # Build a composite index using multiple key fields as a tuple key
  defp build_composite_index(source_table, index_table, key_fields) do
    source_name = table_name(source_table)
    index_name = index_table_name(index_table)

    # Group items by a tuple of the key field values
    groups =
      :ets.tab2list(source_name)
      |> Enum.group_by(
        fn {_id, data} ->
          Enum.map(key_fields, &Map.get(data, &1)) |> List.to_tuple()
        end,
        fn {id, _data} -> id end
      )

    # Insert each group into the index table
    for {key, ids} <- groups, not Enum.any?(Tuple.to_list(key), &is_nil/1) do
      :ets.insert(index_name, {key, ids})
    end
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
