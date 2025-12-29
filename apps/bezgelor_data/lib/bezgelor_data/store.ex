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
  alias BezgelorData.Store.Core
  alias BezgelorData.Store.Creatures
  alias BezgelorData.Store.Events
  alias BezgelorData.Store.Index
  alias BezgelorData.Store.Items
  alias BezgelorData.Store.Loader
  alias BezgelorData.Store.Spells
  alias BezgelorData.Store.Splines

  @tables [
    :creatures,
    :creatures_full,
    :zones,
    :spells,
    :items,
    :item_types,
    :class_entries,
    :spell4_entries,
    :spell4_bases,
    :spell4_effects,
    :spell_levels,
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
    :bindpoint_spawns,
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
    :entity_splines,
    # Telegraph data (shape-based spell targeting)
    :telegraph_damage,
    :spell_telegraphs
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
    :spline_nodes_by_spline,
    # Telegraph lookups by spell ID
    :telegraphs_by_spell,
    # Spell effect lookups by spell ID
    :spell4_effects_by_spell
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get an item by ID from the specified table.
  """
  defdelegate get(table, id), to: Core

  @doc """
  List all items from the specified table.

  Note: For large tables, consider using `list_paginated/2` instead to avoid
  loading 50,000+ items into memory at once.
  """
  defdelegate list(table), to: Core

  @doc """
  List items with pagination.

  Returns `{items, continuation}` where continuation is nil when no more pages.
  Uses ETS match with continuation for memory-efficient iteration over large tables.
  """
  defdelegate list_paginated(table, limit \\ 100), to: Core

  @doc """
  Continue paginated iteration from a previous call.
  """
  defdelegate list_continue(continuation), to: Core

  @doc """
  List items matching a filter with pagination.
  """
  defdelegate list_filtered(table, filter_fn, limit \\ 100), to: Core

  @doc """
  Continue filtered pagination from a previous call.
  """
  defdelegate list_filtered_continue(continuation), to: Core

  @doc """
  Collect all pages into a list (convenience function for small filtered results).
  """
  defdelegate collect_all_pages(result, continue_fn), to: Core

  @doc """
  Get the count of items in a table.
  """
  defdelegate count(table), to: Core

  @doc """
  Reload data from files. Used for development/testing.
  """
  @spec reload() :: :ok
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # Tradeskill queries - delegated to Queries.Tradeskill module
  defdelegate get_profession(id), to: BezgelorData.Queries.Tradeskill
  defdelegate get_professions_by_type(type), to: BezgelorData.Queries.Tradeskill
  defdelegate get_schematic(id), to: BezgelorData.Queries.Tradeskill
  defdelegate get_schematics_for_profession(profession_id), to: BezgelorData.Queries.Tradeskill

  defdelegate get_available_schematics(profession_id, skill_level),
    to: BezgelorData.Queries.Tradeskill

  defdelegate get_talent(id), to: BezgelorData.Queries.Tradeskill
  defdelegate get_talents_for_profession(profession_id), to: BezgelorData.Queries.Tradeskill
  defdelegate get_additive(id), to: BezgelorData.Queries.Tradeskill
  defdelegate get_additive_by_item(item_id), to: BezgelorData.Queries.Tradeskill
  defdelegate get_node_type(id), to: BezgelorData.Queries.Tradeskill
  defdelegate get_node_types_for_profession(profession_id), to: BezgelorData.Queries.Tradeskill
  defdelegate get_node_types_for_level(profession_id, level), to: BezgelorData.Queries.Tradeskill
  defdelegate get_work_order_template(id), to: BezgelorData.Queries.Tradeskill
  defdelegate get_work_orders_for_profession(profession_id), to: BezgelorData.Queries.Tradeskill

  defdelegate get_available_work_orders(profession_id, skill_level),
    to: BezgelorData.Queries.Tradeskill

  # Public Events queries

  # Event and World Boss queries - delegated to Store.Events
  defdelegate get_public_event(id), to: Events
  defdelegate get_zone_public_events(zone_id), to: Events
  defdelegate get_world_boss(id), to: Events
  defdelegate get_zone_world_bosses(zone_id), to: Events
  defdelegate get_event_spawn_points(zone_id), to: Events
  defdelegate get_spawn_point_group(zone_id, group_name), to: Events
  defdelegate get_event_loot_table(id), to: Events
  defdelegate get_loot_table_for_event(event_id), to: Events
  defdelegate get_loot_table_for_world_boss(boss_id), to: Events
  defdelegate get_tier_drops(loot_table_id, tier), to: Events

  # Instance/Dungeon queries - delegated to Queries.Instances module
  defdelegate get_instance(id), to: BezgelorData.Queries.Instances
  defdelegate get_instances_by_type(type), to: BezgelorData.Queries.Instances
  defdelegate get_available_instances(player_level), to: BezgelorData.Queries.Instances
  defdelegate get_instances_with_difficulty(difficulty), to: BezgelorData.Queries.Instances
  defdelegate get_instance_boss(id), to: BezgelorData.Queries.Instances
  defdelegate get_bosses_for_instance(instance_id), to: BezgelorData.Queries.Instances
  defdelegate get_required_bosses(instance_id), to: BezgelorData.Queries.Instances
  defdelegate get_optional_bosses(instance_id), to: BezgelorData.Queries.Instances
  defdelegate get_mythic_affix(id), to: BezgelorData.Queries.Instances
  defdelegate get_all_mythic_affixes(), to: BezgelorData.Queries.Instances
  defdelegate get_affixes_for_level(keystone_level), to: BezgelorData.Queries.Instances
  defdelegate get_affixes_by_tier(tier), to: BezgelorData.Queries.Instances
  defdelegate get_weekly_affix_rotation(week), to: BezgelorData.Queries.Instances

  # PvP queries - delegated to Queries.PvP module
  defdelegate get_battleground(id), to: BezgelorData.Queries.PvP
  defdelegate get_all_battlegrounds(), to: BezgelorData.Queries.PvP
  defdelegate get_available_battlegrounds(player_level), to: BezgelorData.Queries.PvP
  defdelegate get_battlegrounds_by_type(type), to: BezgelorData.Queries.PvP
  defdelegate get_arena(id), to: BezgelorData.Queries.PvP
  defdelegate get_all_arenas(), to: BezgelorData.Queries.PvP
  defdelegate get_arenas_for_bracket(bracket), to: BezgelorData.Queries.PvP
  defdelegate get_arena_bracket(bracket), to: BezgelorData.Queries.PvP
  defdelegate get_arena_rating_rewards(), to: BezgelorData.Queries.PvP
  defdelegate get_warplot_plug(id), to: BezgelorData.Queries.PvP
  defdelegate get_all_warplot_plugs(), to: BezgelorData.Queries.PvP
  defdelegate get_warplot_plugs_by_category(category), to: BezgelorData.Queries.PvP
  defdelegate get_warplot_plug_categories(), to: BezgelorData.Queries.PvP
  defdelegate get_warplot_socket_layout(), to: BezgelorData.Queries.PvP
  defdelegate get_warplot_settings(), to: BezgelorData.Queries.PvP

  # Creature Spawn queries - delegated to Queries.Spawns module
  defdelegate get_creature_spawns(world_id), to: BezgelorData.Queries.Spawns
  defdelegate get_all_spawn_zones(), to: BezgelorData.Queries.Spawns
  defdelegate get_spawns_in_area(world_id, area_id), to: BezgelorData.Queries.Spawns
  defdelegate get_spawns_for_creature(creature_id), to: BezgelorData.Queries.Spawns
  defdelegate get_resource_spawns(world_id), to: BezgelorData.Queries.Spawns
  defdelegate get_object_spawns(world_id), to: BezgelorData.Queries.Spawns
  defdelegate get_spawn_count(world_id), to: BezgelorData.Queries.Spawns
  defdelegate get_total_spawn_count(), to: BezgelorData.Queries.Spawns

  # Bindpoint/Graveyard queries - delegated to Queries.Spawns module
  defdelegate get_all_bindpoints(), to: BezgelorData.Queries.Spawns
  defdelegate get_bindpoints_for_world(world_id), to: BezgelorData.Queries.Spawns
  defdelegate find_nearest_bindpoint(world_id, position), to: BezgelorData.Queries.Spawns
  defdelegate get_bindpoint_by_creature_id(creature_id), to: BezgelorData.Queries.Spawns

  # Telegraph and Spell queries - delegated to Store.Spells
  defdelegate get_telegraph_damage(telegraph_id), to: Spells
  defdelegate get_telegraphs_for_spell(spell_id), to: Spells
  defdelegate get_telegraph_shapes_for_spell(spell_id), to: Spells
  defdelegate get_spell4_effect(effect_id), to: Spells
  defdelegate get_spell_effect_ids(spell_id), to: Spells
  defdelegate get_spell_effects(spell_id), to: Spells
  defdelegate spell_has_telegraphs?(spell_id), to: Spells

  # Patrol path and spline queries - delegated to Store.Splines
  defdelegate get_patrol_path(path_name), to: Splines
  defdelegate list_patrol_paths(), to: Splines
  defdelegate get_spline(spline_id), to: Splines
  defdelegate get_spline_nodes(spline_id), to: Splines
  defdelegate get_splines_for_world(world_id), to: Splines
  defdelegate find_nearest_spline(world_id, position, opts \\ []), to: Splines
  defdelegate build_spline_spatial_index(), to: Splines
  defdelegate find_nearest_spline_indexed(spatial_index, world_id, position, opts \\ []), to: Splines
  defdelegate get_spline_as_patrol(spline_id), to: Splines
  defdelegate find_entity_spline(world_id, creature_id, position), to: Splines

  # Quest queries - delegated to Queries.Quests module
  defdelegate get_quest(id), to: BezgelorData.Queries.Quests
  defdelegate get_quests_for_zone(zone_id), to: BezgelorData.Queries.Quests
  defdelegate get_quests_by_type(type), to: BezgelorData.Queries.Quests
  defdelegate get_quest_objective(id), to: BezgelorData.Queries.Quests
  defdelegate get_quest_rewards(quest_id), to: BezgelorData.Queries.Quests
  defdelegate get_quest_category(id), to: BezgelorData.Queries.Quests
  defdelegate get_quest_hub(id), to: BezgelorData.Queries.Quests
  defdelegate get_quests_for_creature_giver(creature_id), to: BezgelorData.Queries.Quests
  defdelegate get_quests_for_creature_receiver(creature_id), to: BezgelorData.Queries.Quests
  defdelegate get_quest_with_objectives(quest_id), to: BezgelorData.Queries.Quests
  defdelegate creature_quest_giver?(creature_id), to: BezgelorData.Queries.Quests
  defdelegate creature_quest_receiver?(creature_id), to: BezgelorData.Queries.Quests

  # NPC/Vendor queries - delegated to Queries.Quests module
  defdelegate get_vendor(id), to: BezgelorData.Queries.Quests
  defdelegate get_vendor_by_creature(creature_id), to: BezgelorData.Queries.Quests
  defdelegate get_vendors_by_type(vendor_type), to: BezgelorData.Queries.Quests
  defdelegate get_all_vendors(), to: BezgelorData.Queries.Quests
  defdelegate get_vendor_inventory(vendor_id), to: BezgelorData.Queries.Quests
  defdelegate get_vendor_items_for_creature(creature_id), to: BezgelorData.Queries.Quests
  defdelegate get_creature_affiliation(id), to: BezgelorData.Queries.Quests
  defdelegate get_creature_full(id), to: BezgelorData.Queries.Quests

  # Gossip/Dialogue queries - delegated to Queries.Quests module
  defdelegate get_gossip_entry(id), to: BezgelorData.Queries.Quests
  defdelegate get_gossip_entries_for_set(set_id), to: BezgelorData.Queries.Quests
  defdelegate get_gossip_set(id), to: BezgelorData.Queries.Quests

  # Achievement queries - delegated to Queries.Achievements module
  defdelegate get_achievement(id), to: BezgelorData.Queries.Achievements
  defdelegate get_achievements_for_category(category_id), to: BezgelorData.Queries.Achievements
  defdelegate get_achievements_for_zone(zone_id), to: BezgelorData.Queries.Achievements
  defdelegate get_achievement_category(id), to: BezgelorData.Queries.Achievements
  defdelegate get_achievement_checklists(achievement_id), to: BezgelorData.Queries.Achievements

  # Path queries - delegated to Queries.Achievements module
  defdelegate get_path_mission(id), to: BezgelorData.Queries.Achievements
  defdelegate get_path_missions_for_episode(episode_id), to: BezgelorData.Queries.Achievements
  defdelegate get_path_missions_by_type(path_type), to: BezgelorData.Queries.Achievements
  defdelegate get_path_episode(id), to: BezgelorData.Queries.Achievements
  defdelegate get_path_reward(id), to: BezgelorData.Queries.Achievements
  defdelegate get_path_episodes_for_zone(world_id, zone_id), to: BezgelorData.Queries.Achievements

  defdelegate get_zone_path_missions(world_id, zone_id, path_type),
    to: BezgelorData.Queries.Achievements

  # Challenge queries - delegated to Queries.Achievements module
  defdelegate get_challenge(id), to: BezgelorData.Queries.Achievements
  defdelegate get_challenges_for_zone(zone_id), to: BezgelorData.Queries.Achievements
  defdelegate get_challenge_tier(id), to: BezgelorData.Queries.Achievements

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
  defdelegate get_creature_loot_rules(), to: Creatures

  @doc """
  Get loot table override for a specific creature.
  """
  defdelegate get_creature_loot_override(creature_id), to: Creatures

  @doc """
  Get loot category tables mapping.
  """
  defdelegate get_loot_category_tables(), to: Creatures

  # Harvest node loot queries

  @doc """
  Get harvest node loot data by creature ID.
  """
  defdelegate get_harvest_loot(creature_id), to: Creatures

  @doc """
  Get all harvest loot mappings.
  """
  defdelegate get_all_harvest_loot(), to: Creatures

  @doc """
  Get harvest loot by tradeskill ID.
  """
  defdelegate get_harvest_loot_by_tradeskill(tradeskill_id), to: Creatures

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

  defdelegate get_item_visuals(race, sex, customizations), to: Items

  defdelegate get_item_slot(item_id), to: Items
  defdelegate get_item_equipped_slot(item_id), to: Items
  defdelegate get_class_gear_visuals(class_id), to: Items
  defdelegate get_item_display_id(item_id), to: Items
  defdelegate get_item_display_id(item_id, power_level), to: Items
  defdelegate get_item_visual_info(item_id), to: Items
  defdelegate get_item_visual_info(item_id, power_level), to: Items
  defdelegate get_item_model_path(item_id), to: Items
  defdelegate get_item_model_path(item_id, power_level), to: Items
  defdelegate get_display_model_path(display_id), to: Items

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

  # Helper to get item field with both atom and string key support
  defp get_item_field(item, field) when is_atom(field) do
    Map.get(item, field) || Map.get(item, Atom.to_string(field))
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

  defdelegate resolve_creature_loot(creature_id), to: Creatures

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

  # Table name helpers - public for query modules

  @doc """
  Get the ETS table name for a data table.
  Used by query modules for direct ETS access.
  """
  defdelegate table_name(table), to: Core

  @doc """
  Get the ETS table name for an index table.
  Used by query modules for direct ETS access.
  """
  defdelegate index_table_name(table), to: Index

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
      fn -> load_client_table(:class_entries, "Class.json", "class") end,
      fn ->
        load_client_table_parts(
          :spell4_entries,
          [
            "Spell4_part1.json",
            "Spell4_part2.json",
            "Spell4_part3.json",
            "Spell4_part4.json",
            "Spell4_part5.json",
            "Spell4_part6.json",
            "Spell4_part7.json"
          ],
          "spell4"
        )
      end,
      fn ->
        load_client_table_parts(
          :spell4_bases,
          [
            "Spell4Base_part1.json",
            "Spell4Base_part2.json"
          ],
          "spell4base"
        )
      end,
      fn ->
        load_client_table_parts(
          :spell4_effects,
          [
            "Spell4Effects_part1.json",
            "Spell4Effects_part2.json",
            "Spell4Effects_part3.json",
            "Spell4Effects_part4.json"
          ],
          "spell4effects"
        )
      end,
      fn -> load_client_table(:spell_levels, "SpellLevel.json", "spelllevel") end,
      fn -> load_client_table(:item_types, "Item2Type.json", "item2type") end,
      fn ->
        load_client_table(
          :creation_armor_sets,
          "CharacterCreationArmorSet.json",
          "charactercreationarmorset"
        )
      end,
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
      fn ->
        load_table(:tradeskill_work_orders, "tradeskill_work_orders.json", "work_order_templates")
      end,
      # Public events data
      fn -> load_table(:public_events, "public_events.json", "public_events") end,
      fn -> load_table(:world_bosses, "world_bosses.json", "world_bosses") end,
      fn ->
        load_table_by_zone(:event_spawn_points, "event_spawn_points.json", "event_spawn_points")
      end,
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
      fn -> load_bindpoint_spawns() end,
      # Quest data
      fn -> load_client_table(:quests, "quests.json", "quest2") end,
      fn -> load_client_table(:quest_objectives, "quest_objectives.json", "questobjective") end,
      fn ->
        load_client_table_with_fk(:quest_rewards, "quest_rewards.json", "quest2reward", :quest2Id)
      end,
      fn -> load_client_table(:quest_categories, "quest_categories.json", "questcategory") end,
      fn -> load_client_table(:quest_hubs, "quest_hubs.json", "questhub") end,
      # NPC/Vendor data
      fn -> load_table(:npc_vendors, "npc_vendors.json", "npc_vendors") end,
      fn -> load_vendor_inventories() end,
      fn ->
        load_client_table(
          :creature_affiliations,
          "creature_affiliations.json",
          "creature2affiliation"
        )
      end,
      # Dialogue data
      fn -> load_client_table(:gossip_entries, "gossip_entries.json", "gossipentry") end,
      fn -> load_client_table(:gossip_sets, "gossip_sets.json", "gossipset") end,
      # Achievement data
      fn -> load_client_table(:achievements, "achievements.json", "achievement") end,
      fn ->
        load_client_table(
          :achievement_categories,
          "achievement_categories.json",
          "achievementcategory"
        )
      end,
      fn ->
        load_client_table(
          :achievement_checklists,
          "achievement_checklists.json",
          "achievementchecklist"
        )
      end,
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
      fn ->
        load_client_table(:character_creations, "CharacterCreation.json", "charactercreation")
      end,
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
      fn -> load_entity_splines() end,
      # Telegraph data (shape-based spell targeting)
      fn -> load_telegraph_data() end
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

  defp load_table(table, json_file, key), do: Loader.load_table(table, json_file, key)
  defp load_table_by_zone(table, json_file, key), do: Loader.load_table_by_zone(table, json_file, key)
  defp load_client_table(table, json_file, key), do: Loader.load_client_table(table, json_file, key)
  defp load_client_table_parts(table, json_files, key), do: Loader.load_client_table_parts(table, json_files, key)
  defp load_client_table_with_fk(table, json_file, key, fk_field), do: Loader.load_client_table_with_fk(table, json_file, key, fk_field)

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

        Logger.debug(
          "Loaded #{length(inventories)} vendor inventories (#{total_items} total items)"
        )

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

  # Delegate to Loader for JSON/ETF handling
  defp load_json_raw(path), do: Loader.load_json_raw(path)

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
        timeout: 300_000
      )
      |> Enum.reduce([], fn {:ok, {:ok, tuples}}, acc -> acc ++ tuples end)

    # Bulk insert all at once
    :ets.insert(table_name, results)

    Logger.debug(
      "Loaded #{length(results)} full creature records from #{length(part_files)} parts (parallel)"
    )
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

              tuples =
                Enum.map(items, fn item ->
                  id = Map.get(item, :ID)
                  normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
                  {id, normalized}
                end)

              {:ok, tuples}

            {:error, reason} ->
              Logger.warning("Failed to load #{filename}: #{inspect(reason)}")
              {:ok, []}
          end
        end,
        max_concurrency: 4,
        timeout: 300_000
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

              tuples =
                Enum.map(spells, fn spell ->
                  id = Map.get(spell, :ID)
                  normalized = spell |> Map.put(:id, id) |> Map.delete(:ID)
                  {id, normalized}
                end)

              {:ok, tuples}

            {:error, reason} ->
              Logger.warning("Failed to load #{filename}: #{inspect(reason)}")
              {:ok, []}
          end
        end,
        max_concurrency: 4,
        timeout: 300_000
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
            normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
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

        tuples =
          items
          |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
          |> Enum.map(fn item ->
            id = Map.get(item, :ID)
            normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
            {id, normalized}
          end)

        :ets.insert(table_name, tuples)
        build_display_source_index(items)
        Logger.debug("Loaded #{length(tuples)} item display source entries")

      {:error, _reason} ->
        Logger.debug("ItemDisplaySourceEntry.json not found (optional)")
    end
  end

  # Build the display_sources_by_source_id index for efficient lookup
  defp build_display_source_index(items) do
    index_name = index_table_name(:display_sources_by_source_id)

    tuples =
      items
      |> Enum.group_by(fn item -> Map.get(item, :itemSourceId) || 0 end)
      |> Enum.filter(fn {source_id, _} -> source_id > 0 end)

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
            normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
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

    Logger.debug(
      "Creature spawns: checking ETF at #{enriched_etf_path}, exists? #{File.exists?(enriched_etf_path)}"
    )

    is_fresh = enriched_etf_cache_fresh?(enriched_etf_path)
    Logger.debug("Creature spawns: enriched ETF fresh? #{is_fresh}")

    if is_fresh do
      result = load_creature_spawns_from_etf(enriched_etf_path, table_name)
      Logger.debug("Loaded creature spawns from enriched ETF cache: #{result}")
      result
    else
      Logger.debug("Enriched ETF not fresh, loading from JSON and will re-enrich")
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

    result =
      with {:ok, etf_stat} <- File.stat(etf_path),
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
          # Use [:safe] to prevent arbitrary code execution from tampered cache files
          zone_data_list = :erlang.binary_to_term(content, [:safe])

          for {world_id, zone_data} <- zone_data_list do
            :ets.insert(table_name, {world_id, zone_data})
          end

          total_creatures =
            Enum.reduce(zone_data_list, 0, fn {_wid, z}, acc ->
              acc + length(z.creature_spawns)
            end)

          total_resources =
            Enum.reduce(zone_data_list, 0, fn {_wid, z}, acc ->
              acc + length(z.resource_spawns)
            end)

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
          _e ->
            Logger.debug("ETF cache invalid (expected on restart), loading from JSON")
            load_creature_spawns_from_json(table_name)
        end

      {:error, _reason} ->
        Logger.debug("ETF cache not found, loading from JSON")
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
    Logger.debug("Spawn enrichment: ETF fresh? #{is_fresh}")

    if is_fresh do
      Logger.debug("Spawn enrichment: skipping (using cached data)")
      :skipped
    else
      Logger.debug("Spawn enrichment: running enrichment process")
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
                          patrol_speed:
                            if(spline_config.speed < 0, do: 3.0, else: spline_config.speed),
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
    _total_enriched =
      Enum.reduce(enriched_zones, 0, fn {world_id, zone_data, count}, acc ->
        :ets.insert(creature_table, {world_id, zone_data})
        acc + count
      end)

    # Save enriched data to ETF cache for fast subsequent loads
    save_enriched_spawns_to_etf(etf_path, enriched_zones)

    Logger.debug("Enriched creature spawns with patrol paths (cached)")
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

  # Load bindpoint/graveyard spawn data
  defp load_bindpoint_spawns do
    table_name = table_name(:bindpoint_spawns)

    # Clear existing data
    :ets.delete_all_objects(table_name)

    json_path = Path.join(data_directory(), "bindpoint_spawns.json")

    case load_json_raw(json_path) do
      {:ok, data} ->
        bindpoints = Map.get(data, :bindpoint_spawns, [])

        # Store each bindpoint keyed by world_id for efficient per-zone lookup
        by_world = Enum.group_by(bindpoints, & &1.world_id)

        for {world_id, world_bindpoints} <- by_world do
          :ets.insert(table_name, {world_id, world_bindpoints})
        end

        Logger.info(
          "Loaded #{length(bindpoints)} bindpoint spawn locations across #{map_size(by_world)} worlds"
        )

      {:error, reason} ->
        Logger.warning("No bindpoint spawn data found: #{inspect(reason)}")
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

        _total = Map.get(data, :total_count, 0)
        worlds = map_size(by_world)
        Logger.debug("Loaded entity spline mappings across #{worlds} worlds")

      {:error, reason} ->
        Logger.warning("No entity spline data found: #{inspect(reason)}")
    end
  end

  # Load telegraph data (shape-based spell targeting from TelegraphDamage.tbl and Spell4Telegraph.tbl)
  defp load_telegraph_data do
    # Load telegraph damage shapes (circles, cones, rectangles, etc.)
    telegraph_table = table_name(:telegraph_damage)
    :ets.delete_all_objects(telegraph_table)

    telegraph_path = Path.join(data_directory(), "telegraph_damage.json")

    telegraph_count =
      case load_json_raw(telegraph_path) do
        {:ok, data} ->
          items = Map.get(data, :telegraphdamage, [])

          tuples =
            items
            |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
            |> Enum.map(fn item ->
              id = Map.get(item, :ID)
              normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
              {id, normalized}
            end)

          :ets.insert(telegraph_table, tuples)
          length(tuples)

        {:error, reason} ->
          Logger.warning("Failed to load telegraph damage data: #{inspect(reason)}")
          0
      end

    # Load spell->telegraph mappings
    spell_telegraph_table = table_name(:spell_telegraphs)
    index_table = index_table_name(:telegraphs_by_spell)
    :ets.delete_all_objects(spell_telegraph_table)
    :ets.delete_all_objects(index_table)

    spell_telegraph_path = Path.join(data_directory(), "spell4_telegraph.json")

    spell_telegraph_count =
      case load_json_raw(spell_telegraph_path) do
        {:ok, data} ->
          items = Map.get(data, :spell4telegraph, [])

          tuples =
            items
            |> Enum.filter(fn item -> Map.has_key?(item, :ID) end)
            |> Enum.map(fn item ->
              id = Map.get(item, :ID)
              normalized = item |> Map.put(:id, id) |> Map.delete(:ID)
              {id, normalized}
            end)

          :ets.insert(spell_telegraph_table, tuples)

          # Build index: spell_id -> [telegraph_damage_id, ...]
          by_spell =
            items
            |> Enum.group_by(fn item -> Map.get(item, :spell4Id) end)

          for {spell_id, entries} <- by_spell, spell_id != nil do
            telegraph_ids = Enum.map(entries, fn e -> Map.get(e, :telegraphDamageId) end)
            :ets.insert(index_table, {spell_id, telegraph_ids})
          end

          length(tuples)

        {:error, reason} ->
          Logger.warning("Failed to load spell telegraph data: #{inspect(reason)}")
          0
      end

    Logger.info(
      "Loaded #{telegraph_count} telegraph shapes and #{spell_telegraph_count} spell->telegraph mappings"
    )
  end

  # Secondary index building

  # Build all secondary indexes
  defp build_all_indexes do
    Logger.debug("Building secondary indexes...")

    # Clear all index tables EXCEPT those built during load functions:
    # - customizations_by_race_sex (built during load_character_customizations)
    # - display_sources_by_source_id (built during load_item_display_sources)
    skip_tables = [:customizations_by_race_sex, :display_sources_by_source_id]

    for table <- @index_tables, table not in skip_tables do
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
      fn ->
        build_composite_index(:path_episodes, :path_episodes_by_zone, [:worldId, :worldZoneId])
      end,
      # Challenge indexes
      fn -> build_index(:challenges, :challenges_by_zone, :worldZoneId) end,
      # World location indexes
      fn -> build_index(:world_locations, :world_locations_by_world, :worldId) end,
      fn -> build_index(:world_locations, :world_locations_by_zone, :worldZoneId) end,
      # Spline node index
      fn -> build_index(:spline_nodes, :spline_nodes_by_spline, :spline_id) end,
      # Spell effect index (by spell ID for fast lookup)
      fn -> build_index(:spell4_effects, :spell4_effects_by_spell, :spellId) end
    ]

    Enum.each(index_builders, fn builder -> builder.() end)

    Logger.debug("Built #{length(index_builders)} secondary indexes")
  end

  # Delegate index building to Index module
  defp build_index(source_table, index_table, key_field), do: Index.build_index(source_table, index_table, key_field)
  defp build_index_string(source_table, index_table, key_field), do: Index.build_index_string(source_table, index_table, key_field)
  defp build_composite_index(source_table, index_table, key_fields), do: Index.build_composite_index(source_table, index_table, key_fields)

  @doc """
  Lookup IDs from a secondary index table.
  """
  defdelegate lookup_index(index_table, key), to: Index

  @doc """
  Fetch full records from a table for a list of IDs.
  """
  defdelegate fetch_by_ids(table, ids), to: Index

  defp data_directory, do: Loader.data_directory()
  defp compiled_directory, do: Loader.compiled_directory()

  defp stats do
    for table <- @tables, into: %{} do
      {table, count(table)}
    end
  end

end
