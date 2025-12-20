defmodule BezgelorData do
  @moduledoc """
  Static game data access.

  Provides access to game data loaded from JSON files at application startup.
  Data is stored in ETS tables for fast concurrent access.

  ## Data Types

  - **Creatures** - NPC/mob templates (from Creature2.tbl)
  - **Zones** - World zone definitions (from WorldZone.tbl)
  - **Spells** - Spell/ability definitions (from Spell4.tbl)
  - **Items** - Item templates (from Item2.tbl)

  ## Data Fields

  ### Creatures
  - id, name_text_id, description, race_id, difficulty_id
  - archetype_id, tier_id, model_info_id, display_group_id
  - outfit_group_id, model_scale, creation_type, aoi_size, spells

  ### Zones
  - id, name_text_id, parent_zone_id, allow_access, color
  - sound_zone_kit_id, exit_location_id, flags, pvp_rules, reward_rotation_id

  ### Spells
  - id, description, base_spell_id, tier_index, cast_time
  - duration, cooldown, min_range, max_range, ravel_instance_id

  ### Items
  - id, name_text_id, tooltip_text_id, family_id, category_id
  - type_id, quality_id, display_id, power_level, required_level
  - required_item_level, class_required, race_required, faction_required
  - equipped_slot_flags, max_stack_count, max_charges, flags, bind_flags
  - stat_id, budget_id

  ## Usage

      # Get a specific creature
      {:ok, creature} = BezgelorData.get_creature(1)

      # List all zones
      zones = BezgelorData.list_zones()

      # Find creatures by tier
      creatures = BezgelorData.creatures_by_tier(1)
  """

  alias BezgelorData.Store

  # Creatures

  @doc """
  Get a creature template by ID.
  """
  @spec get_creature(non_neg_integer()) :: {:ok, map()} | :error
  def get_creature(id) do
    Store.get(:creatures, id)
  end

  @doc """
  Get a creature template by ID, raising if not found.
  """
  @spec get_creature!(non_neg_integer()) :: map()
  def get_creature!(id) do
    case get_creature(id) do
      {:ok, creature} -> creature
      :error -> raise "Creature #{id} not found"
    end
  end

  @doc """
  List all creature templates.
  """
  @spec list_creatures() :: [map()]
  def list_creatures do
    Store.list(:creatures)
  end

  @doc """
  Find creatures by tier.
  """
  @spec creatures_by_tier(non_neg_integer()) :: [map()]
  def creatures_by_tier(tier_id) do
    list_creatures()
    |> Enum.filter(fn c -> c.tier_id == tier_id end)
  end

  @doc """
  Find creatures by difficulty.
  """
  @spec creatures_by_difficulty(non_neg_integer()) :: [map()]
  def creatures_by_difficulty(difficulty_id) do
    list_creatures()
    |> Enum.filter(fn c -> c.difficulty_id == difficulty_id end)
  end

  @doc """
  Find creatures by archetype.
  """
  @spec creatures_by_archetype(non_neg_integer()) :: [map()]
  def creatures_by_archetype(archetype_id) do
    list_creatures()
    |> Enum.filter(fn c -> c.archetype_id == archetype_id end)
  end

  # Zones

  @doc """
  Get a zone by ID.
  """
  @spec get_zone(non_neg_integer()) :: {:ok, map()} | :error
  def get_zone(id) do
    Store.get(:zones, id)
  end

  @doc """
  Get a zone by ID, raising if not found.
  """
  @spec get_zone!(non_neg_integer()) :: map()
  def get_zone!(id) do
    case get_zone(id) do
      {:ok, zone} -> zone
      :error -> raise "Zone #{id} not found"
    end
  end

  @doc """
  List all zones.
  """
  @spec list_zones() :: [map()]
  def list_zones do
    Store.list(:zones)
  end

  @doc """
  List zones by PvP rules (0 = no PvP, 5 = PvP enabled, etc).
  """
  @spec zones_by_pvp_rules(non_neg_integer()) :: [map()]
  def zones_by_pvp_rules(pvp_rules) do
    list_zones()
    |> Enum.filter(fn z -> z.pvp_rules == pvp_rules end)
  end

  @doc """
  List child zones of a parent zone.
  """
  @spec child_zones(non_neg_integer()) :: [map()]
  def child_zones(parent_zone_id) do
    list_zones()
    |> Enum.filter(fn z -> z.parent_zone_id == parent_zone_id end)
  end

  @doc """
  List root zones (zones with no parent).
  """
  @spec root_zones() :: [map()]
  def root_zones do
    list_zones()
    |> Enum.filter(fn z -> z.parent_zone_id == nil end)
  end

  @doc """
  List accessible zones.
  """
  @spec accessible_zones() :: [map()]
  def accessible_zones do
    list_zones()
    |> Enum.filter(fn z -> z.allow_access == true end)
  end

  # Spells

  @doc """
  Get a spell by ID.
  """
  @spec get_spell(non_neg_integer()) :: {:ok, map()} | :error
  def get_spell(id) do
    Store.get(:spells, id)
  end

  @doc """
  Get a spell by ID, raising if not found.
  """
  @spec get_spell!(non_neg_integer()) :: map()
  def get_spell!(id) do
    case get_spell(id) do
      {:ok, spell} -> spell
      :error -> raise "Spell #{id} not found"
    end
  end

  @doc """
  List all spells.
  """
  @spec list_spells() :: [map()]
  def list_spells do
    Store.list(:spells)
  end

  @doc """
  Get a class entry by ID.
  """
  @spec get_class_entry(non_neg_integer()) :: {:ok, map()} | :error
  def get_class_entry(class_id) do
    Store.get(:class_entries, class_id)
  end

  @doc """
  List all class entries.
  """
  @spec list_class_entries() :: [map()]
  def list_class_entries do
    Store.list(:class_entries)
  end

  @doc """
  Get a Spell4 entry by ID.
  """
  @spec get_spell4_entry(non_neg_integer()) :: {:ok, map()} | :error
  def get_spell4_entry(spell4_id) do
    Store.get(:spell4_entries, spell4_id)
  end

  @doc """
  List all Spell4 entries.
  """
  @spec list_spell4_entries() :: [map()]
  def list_spell4_entries do
    Store.list(:spell4_entries)
  end

  @doc """
  Get a Spell4Base entry by ID.
  """
  @spec get_spell4_base_entry(non_neg_integer()) :: {:ok, map()} | :error
  def get_spell4_base_entry(base_id) do
    Store.get(:spell4_bases, base_id)
  end

  @doc """
  List all Spell4Base entries.
  """
  @spec list_spell4_base_entries() :: [map()]
  def list_spell4_base_entries do
    Store.list(:spell4_bases)
  end

  @doc """
  List all SpellLevel entries.
  """
  @spec list_spell_levels() :: [map()]
  def list_spell_levels do
    Store.list(:spell_levels)
  end

  @doc """
  List SpellLevel entries by class and level.
  """
  @spec spell_levels_for_class_level(non_neg_integer(), non_neg_integer()) :: [map()]
  def spell_levels_for_class_level(class_id, level) do
    list_spell_levels()
    |> Enum.filter(fn entry ->
      entry.classId == class_id and entry.characterLevel == level
    end)
  end

  @doc """
  Find spells by base spell ID.
  """
  @spec spells_by_base(non_neg_integer()) :: [map()]
  def spells_by_base(base_spell_id) do
    list_spells()
    |> Enum.filter(fn s -> s.base_spell_id == base_spell_id end)
  end

  # Items

  @doc """
  Get an item by ID.
  """
  @spec get_item(non_neg_integer()) :: {:ok, map()} | :error
  def get_item(id) do
    Store.get(:items, id)
  end

  @doc """
  Get an item by ID, raising if not found.
  """
  @spec get_item!(non_neg_integer()) :: map()
  def get_item!(id) do
    case get_item(id) do
      {:ok, item} -> item
      :error -> raise "Item #{id} not found"
    end
  end

  @doc """
  List all items.
  """
  @spec list_items() :: [map()]
  def list_items do
    Store.list(:items)
  end

  @doc """
  List items by type ID.
  """
  @spec items_by_type(non_neg_integer()) :: [map()]
  def items_by_type(type_id) do
    list_items()
    |> Enum.filter(fn i -> i.type_id == type_id end)
  end

  @doc """
  List items by quality ID (0=common, 1=uncommon, 2=rare, 3=epic, 4=legendary, 5=artifact).
  """
  @spec items_by_quality(non_neg_integer()) :: [map()]
  def items_by_quality(quality_id) do
    list_items()
    |> Enum.filter(fn i -> i.quality_id == quality_id end)
  end

  @doc """
  List items by family ID.
  """
  @spec items_by_family(non_neg_integer()) :: [map()]
  def items_by_family(family_id) do
    list_items()
    |> Enum.filter(fn i -> i.family_id == family_id end)
  end

  @doc """
  List items by category ID.
  """
  @spec items_by_category(non_neg_integer()) :: [map()]
  def items_by_category(category_id) do
    list_items()
    |> Enum.filter(fn i -> i.category_id == category_id end)
  end

  # Texts

  @doc """
  Get a localized text string by ID.
  """
  @spec get_text(integer()) :: {:ok, String.t()} | :error
  def get_text(text_id) do
    case :ets.lookup(:bezgelor_data_texts, text_id) do
      [{^text_id, text}] -> {:ok, text}
      [] -> :error
    end
  end

  @doc """
  Get a localized text string by ID, raising if not found.
  """
  @spec get_text!(integer()) :: String.t()
  def get_text!(text_id) do
    case get_text(text_id) do
      {:ok, text} -> text
      :error -> raise "Text #{text_id} not found"
    end
  end

  @doc """
  Get a localized text string by ID, returning nil if not found.
  """
  @spec text_or_nil(integer()) :: String.t() | nil
  def text_or_nil(text_id) do
    case get_text(text_id) do
      {:ok, text} -> text
      :error -> nil
    end
  end

  # Convenience functions for entities with names

  @doc """
  Get a creature with its name resolved from the text table.
  Returns the creature map with an additional :name key.
  """
  @spec get_creature_with_name(non_neg_integer()) :: {:ok, map()} | :error
  def get_creature_with_name(id) do
    with {:ok, creature} <- get_creature(id) do
      name = text_or_nil(creature.name_text_id) || ""
      {:ok, Map.put(creature, :name, name)}
    end
  end

  @doc """
  Get a zone with its name resolved from the text table.
  """
  @spec get_zone_with_name(non_neg_integer()) :: {:ok, map()} | :error
  def get_zone_with_name(id) do
    with {:ok, zone} <- get_zone(id) do
      name = text_or_nil(zone.name_text_id) || ""
      {:ok, Map.put(zone, :name, name)}
    end
  end

  @doc """
  Get an item with its name and tooltip resolved from the text table.
  """
  @spec get_item_with_name(non_neg_integer()) :: {:ok, map()} | :error
  def get_item_with_name(id) do
    with {:ok, item} <- get_item(id) do
      name = text_or_nil(item[:localizedTextIdName] || item[:name_text_id]) || ""
      tooltip = text_or_nil(item[:localizedTextIdTooltip] || item[:tooltip_text_id]) || ""
      {:ok, item |> Map.put(:name, name) |> Map.put(:tooltip, tooltip)}
    end
  end

  # Housing Data

  @doc """
  Get a house type definition by ID.
  """
  @spec get_house_type(non_neg_integer()) :: {:ok, map()} | :error
  def get_house_type(id) do
    Store.get(:house_types, id)
  end

  @doc """
  Get a house type by ID, raising if not found.
  """
  @spec get_house_type!(non_neg_integer()) :: map()
  def get_house_type!(id) do
    case get_house_type(id) do
      {:ok, house_type} -> house_type
      :error -> raise "House type #{id} not found"
    end
  end

  @doc """
  List all house types.
  """
  @spec list_house_types() :: [map()]
  def list_house_types do
    Store.list(:house_types)
  end

  @doc """
  Get housing decor definition by ID.
  """
  @spec get_decor(non_neg_integer()) :: {:ok, map()} | :error
  def get_decor(id) do
    Store.get(:housing_decor, id)
  end

  @doc """
  Get decor by ID, raising if not found.
  """
  @spec get_decor!(non_neg_integer()) :: map()
  def get_decor!(id) do
    case get_decor(id) do
      {:ok, decor} -> decor
      :error -> raise "Decor #{id} not found"
    end
  end

  @doc """
  List all housing decor items.
  """
  @spec list_decor() :: [map()]
  def list_decor do
    Store.list(:housing_decor)
  end

  @doc """
  List decor items by category.
  """
  @spec decor_by_category(String.t()) :: [map()]
  def decor_by_category(category) do
    list_decor()
    |> Enum.filter(fn d -> d.category == category end)
  end

  @doc """
  Get housing FABkit definition by ID.
  """
  @spec get_fabkit(non_neg_integer()) :: {:ok, map()} | :error
  def get_fabkit(id) do
    Store.get(:housing_fabkits, id)
  end

  @doc """
  Get FABkit by ID, raising if not found.
  """
  @spec get_fabkit!(non_neg_integer()) :: map()
  def get_fabkit!(id) do
    case get_fabkit(id) do
      {:ok, fabkit} -> fabkit
      :error -> raise "FABkit #{id} not found"
    end
  end

  @doc """
  List all housing FABkits.
  """
  @spec list_fabkits() :: [map()]
  def list_fabkits do
    Store.list(:housing_fabkits)
  end

  @doc """
  List FABkits by type.
  """
  @spec fabkits_by_type(String.t()) :: [map()]
  def fabkits_by_type(type) do
    list_fabkits()
    |> Enum.filter(fn f -> f.type == type end)
  end

  # Titles

  @doc """
  Get a title definition by ID.
  """
  @spec get_title(non_neg_integer()) :: {:ok, map()} | :error
  def get_title(id) do
    Store.get(:titles, id)
  end

  @doc """
  Get a title by ID, raising if not found.
  """
  @spec get_title!(non_neg_integer()) :: map()
  def get_title!(id) do
    case get_title(id) do
      {:ok, title} -> title
      :error -> raise "Title #{id} not found"
    end
  end

  @doc """
  List all titles.
  """
  @spec list_titles() :: [map()]
  def list_titles do
    Store.list(:titles)
  end

  @doc """
  List titles by category.
  """
  @spec titles_by_category(String.t()) :: [map()]
  def titles_by_category(category) do
    list_titles()
    |> Enum.filter(fn t -> t.category == category end)
  end

  @doc """
  List titles by unlock type.
  """
  @spec titles_by_unlock_type(String.t()) :: [map()]
  def titles_by_unlock_type(unlock_type) do
    list_titles()
    |> Enum.filter(fn t -> t.unlock_type == unlock_type end)
  end

  @doc """
  Get all titles that unlock for a specific reputation level.
  """
  @spec titles_for_reputation(integer(), atom()) :: [map()]
  def titles_for_reputation(faction_id, level) do
    level_str = Atom.to_string(level)

    list_titles()
    |> Enum.filter(fn t ->
      t.unlock_type == "reputation" and
        get_in(t, [:unlock_requirements, :faction_id]) == faction_id and
        get_in(t, [:unlock_requirements, :level]) == level_str
    end)
  end

  @doc """
  Get all titles that unlock for a specific achievement.
  """
  @spec titles_for_achievement(integer()) :: [map()]
  def titles_for_achievement(achievement_id) do
    list_titles()
    |> Enum.filter(fn t ->
      t.unlock_type == "achievement" and
        get_in(t, [:unlock_requirements, :achievement_id]) == achievement_id
    end)
  end

  @doc """
  Get all titles that unlock for a specific quest.
  """
  @spec titles_for_quest(integer()) :: [map()]
  def titles_for_quest(quest_id) do
    list_titles()
    |> Enum.filter(fn t ->
      t.unlock_type == "quest" and
        get_in(t, [:unlock_requirements, :quest_id]) == quest_id
    end)
  end

  @doc """
  Get all titles that unlock for path progress.
  """
  @spec titles_for_path(String.t(), integer()) :: [map()]
  def titles_for_path(path, level) do
    list_titles()
    |> Enum.filter(fn t ->
      t.unlock_type == "path" and
        get_in(t, [:unlock_requirements, :path]) == path and
        get_in(t, [:unlock_requirements, :level]) <= level
    end)
  end

  # Public Events

  @doc """
  Get a public event definition by ID.
  """
  @spec get_public_event(non_neg_integer()) :: {:ok, map()} | :error
  def get_public_event(id) do
    Store.get_public_event(id)
  end

  @doc """
  Get a public event by ID, raising if not found.
  """
  @spec get_public_event!(non_neg_integer()) :: map()
  def get_public_event!(id) do
    case get_public_event(id) do
      {:ok, event} -> event
      :error -> raise "Public event #{id} not found"
    end
  end

  @doc """
  List all public events.
  """
  @spec list_public_events() :: [map()]
  def list_public_events do
    Store.list(:public_events)
  end

  @doc """
  Get all public events for a zone.
  """
  @spec public_events_for_zone(non_neg_integer()) :: [map()]
  def public_events_for_zone(zone_id) do
    Store.get_zone_public_events(zone_id)
  end

  # World Bosses

  @doc """
  Get a world boss definition by ID.
  """
  @spec get_world_boss(non_neg_integer()) :: {:ok, map()} | :error
  def get_world_boss(id) do
    Store.get_world_boss(id)
  end

  @doc """
  Get a world boss by ID, raising if not found.
  """
  @spec get_world_boss!(non_neg_integer()) :: map()
  def get_world_boss!(id) do
    case get_world_boss(id) do
      {:ok, boss} -> boss
      :error -> raise "World boss #{id} not found"
    end
  end

  @doc """
  List all world bosses.
  """
  @spec list_world_bosses() :: [map()]
  def list_world_bosses do
    Store.list(:world_bosses)
  end

  @doc """
  Get all world bosses for a zone.
  """
  @spec world_bosses_for_zone(non_neg_integer()) :: [map()]
  def world_bosses_for_zone(zone_id) do
    Store.get_zone_world_bosses(zone_id)
  end

  # Event Spawn Points

  @doc """
  Get spawn points for a zone.
  """
  @spec get_event_spawn_points(non_neg_integer()) :: {:ok, map()} | :error
  def get_event_spawn_points(zone_id) do
    Store.get_event_spawn_points(zone_id)
  end

  @doc """
  Get specific spawn point group for a zone.
  """
  @spec get_spawn_point_group(non_neg_integer(), String.t()) :: [map()]
  def get_spawn_point_group(zone_id, group_name) do
    Store.get_spawn_point_group(zone_id, group_name)
  end

  # Quests

  @doc """
  Get a quest definition by ID.
  """
  @spec get_quest(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest(id), do: Store.get_quest(id)

  @doc """
  Get a quest by ID, raising if not found.
  """
  @spec get_quest!(non_neg_integer()) :: map()
  def get_quest!(id) do
    case get_quest(id) do
      {:ok, quest} -> quest
      :error -> raise "Quest #{id} not found"
    end
  end

  @doc """
  List all quests.
  """
  @spec list_quests() :: [map()]
  def list_quests, do: Store.list(:quests)

  @doc """
  Get all quests for a zone.
  """
  @spec quests_for_zone(non_neg_integer()) :: [map()]
  def quests_for_zone(zone_id), do: Store.get_quests_for_zone(zone_id)

  @doc """
  Get quests by type.
  """
  @spec quests_by_type(non_neg_integer()) :: [map()]
  def quests_by_type(type), do: Store.get_quests_by_type(type)

  @doc """
  Get a quest with its title resolved from the text table.
  """
  @spec get_quest_with_title(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_with_title(id) do
    with {:ok, quest} <- get_quest(id) do
      title = text_or_nil(quest.localizedTextIdTitle) || ""
      {:ok, Map.put(quest, :title, title)}
    end
  end

  @doc """
  Get quest rewards for a quest.
  """
  @spec quest_rewards(non_neg_integer()) :: [map()]
  def quest_rewards(quest_id), do: Store.get_quest_rewards(quest_id)

  @doc """
  Get a quest objective by ID.
  """
  @spec get_quest_objective(non_neg_integer()) :: {:ok, map()} | :error
  def get_quest_objective(id), do: Store.get_quest_objective(id)

  # NPC/Vendors

  @doc """
  Get vendor data by vendor ID.
  """
  @spec get_vendor(non_neg_integer()) :: {:ok, map()} | :error
  def get_vendor(id), do: Store.get_vendor(id)

  @doc """
  Get vendor by creature ID.
  """
  @spec get_vendor_by_creature(non_neg_integer()) :: {:ok, map()} | :error
  def get_vendor_by_creature(creature_id), do: Store.get_vendor_by_creature(creature_id)

  @doc """
  Get all vendors of a specific type.
  """
  @spec vendors_by_type(String.t()) :: [map()]
  def vendors_by_type(vendor_type), do: Store.get_vendors_by_type(vendor_type)

  @doc """
  List all vendors.
  """
  @spec list_vendors() :: [map()]
  def list_vendors, do: Store.get_all_vendors()

  @doc """
  Check if a creature is a vendor.
  """
  @spec is_vendor?(non_neg_integer()) :: boolean()
  def is_vendor?(creature_id) do
    case Store.get_vendor_by_creature(creature_id) do
      {:ok, _} -> true
      :error -> false
    end
  end

  @doc """
  Get vendor inventory by vendor ID.
  """
  @spec get_vendor_inventory(non_neg_integer()) :: {:ok, map()} | :error
  def get_vendor_inventory(vendor_id), do: Store.get_vendor_inventory(vendor_id)

  @doc """
  Get items sold by a creature vendor.
  Returns empty list if creature is not a vendor.
  """
  @spec get_vendor_items(non_neg_integer()) :: [map()]
  def get_vendor_items(creature_id), do: Store.get_vendor_items_for_creature(creature_id)

  # Gossip/Dialogue

  @doc """
  Get a gossip entry by ID.
  """
  @spec get_gossip_entry(non_neg_integer()) :: {:ok, map()} | :error
  def get_gossip_entry(id), do: Store.get_gossip_entry(id)

  @doc """
  Get gossip entries for a gossip set.
  """
  @spec gossip_entries_for_set(non_neg_integer()) :: [map()]
  def gossip_entries_for_set(set_id), do: Store.get_gossip_entries_for_set(set_id)

  @doc """
  Get a gossip set by ID.
  """
  @spec get_gossip_set(non_neg_integer()) :: {:ok, map()} | :error
  def get_gossip_set(id), do: Store.get_gossip_set(id)

  @doc """
  Get gossip text for an entry, resolving the text ID.
  """
  @spec get_gossip_text(non_neg_integer()) :: String.t() | nil
  def get_gossip_text(entry_id) do
    with {:ok, entry} <- get_gossip_entry(entry_id) do
      text_or_nil(entry.localizedTextId)
    else
      _ -> nil
    end
  end

  # Achievements

  @doc """
  Get an achievement by ID.
  """
  @spec get_achievement(non_neg_integer()) :: {:ok, map()} | :error
  def get_achievement(id), do: Store.get_achievement(id)

  @doc """
  Get an achievement by ID, raising if not found.
  """
  @spec get_achievement!(non_neg_integer()) :: map()
  def get_achievement!(id) do
    case get_achievement(id) do
      {:ok, achievement} -> achievement
      :error -> raise "Achievement #{id} not found"
    end
  end

  @doc """
  List all achievements.
  """
  @spec list_achievements() :: [map()]
  def list_achievements, do: Store.list(:achievements)

  @doc """
  Get achievements for a category.
  """
  @spec achievements_for_category(non_neg_integer()) :: [map()]
  def achievements_for_category(category_id), do: Store.get_achievements_for_category(category_id)

  @doc """
  Get achievements for a zone.
  """
  @spec achievements_for_zone(non_neg_integer()) :: [map()]
  def achievements_for_zone(zone_id), do: Store.get_achievements_for_zone(zone_id)

  @doc """
  Get an achievement with its title resolved from the text table.
  """
  @spec get_achievement_with_title(non_neg_integer()) :: {:ok, map()} | :error
  def get_achievement_with_title(id) do
    with {:ok, achievement} <- get_achievement(id) do
      title = text_or_nil(achievement.localizedTextIdTitle) || ""
      {:ok, Map.put(achievement, :title, title)}
    end
  end

  # Path Missions

  @doc """
  Get a path mission by ID.
  """
  @spec get_path_mission(non_neg_integer()) :: {:ok, map()} | :error
  def get_path_mission(id), do: Store.get_path_mission(id)

  @doc """
  List all path missions.
  """
  @spec list_path_missions() :: [map()]
  def list_path_missions, do: Store.list(:path_missions)

  @doc """
  Get path missions for an episode.
  """
  @spec path_missions_for_episode(non_neg_integer()) :: [map()]
  def path_missions_for_episode(episode_id), do: Store.get_path_missions_for_episode(episode_id)

  @doc """
  Get path missions by path type (0=Soldier, 1=Settler, 2=Scientist, 3=Explorer).
  """
  @spec path_missions_by_type(non_neg_integer()) :: [map()]
  def path_missions_by_type(path_type), do: Store.get_path_missions_by_type(path_type)

  @doc """
  Get a path episode by ID.
  """
  @spec get_path_episode(non_neg_integer()) :: {:ok, map()} | :error
  def get_path_episode(id), do: Store.get_path_episode(id)

  # Challenges

  @doc """
  Get a challenge by ID.
  """
  @spec get_challenge(non_neg_integer()) :: {:ok, map()} | :error
  def get_challenge(id), do: Store.get_challenge(id)

  @doc """
  List all challenges.
  """
  @spec list_challenges() :: [map()]
  def list_challenges, do: Store.list(:challenges)

  @doc """
  Get challenges for a zone.
  """
  @spec challenges_for_zone(non_neg_integer()) :: [map()]
  def challenges_for_zone(zone_id), do: Store.get_challenges_for_zone(zone_id)

  # World Locations

  @doc """
  Get a world location by ID.
  """
  @spec get_world_location(non_neg_integer()) :: {:ok, map()} | :error
  def get_world_location(id), do: Store.get_world_location(id)

  @doc """
  Get world locations for a world.
  """
  @spec world_locations_for_world(non_neg_integer()) :: [map()]
  def world_locations_for_world(world_id), do: Store.get_world_locations_for_world(world_id)

  @doc """
  Get world locations for a zone.
  """
  @spec world_locations_for_zone(non_neg_integer()) :: [map()]
  def world_locations_for_zone(zone_id), do: Store.get_world_locations_for_zone(zone_id)

  @doc """
  Get a bind point by ID.
  """
  @spec get_bind_point(non_neg_integer()) :: {:ok, map()} | :error
  def get_bind_point(id), do: Store.get_bind_point(id)

  # Prerequisites

  @doc """
  Get a prerequisite by ID.
  """
  @spec get_prerequisite(non_neg_integer()) :: {:ok, map()} | :error
  def get_prerequisite(id), do: Store.get_prerequisite(id)

  # Stats

  @doc """
  Get statistics about loaded data.
  """
  @spec stats() :: map()
  def stats do
    %{
      creatures: Store.count(:creatures),
      zones: Store.count(:zones),
      spells: Store.count(:spells),
      items: Store.count(:items),
      texts: Store.count(:texts),
      house_types: Store.count(:house_types),
      housing_decor: Store.count(:housing_decor),
      housing_fabkits: Store.count(:housing_fabkits),
      titles: Store.count(:titles),
      public_events: Store.count(:public_events),
      world_bosses: Store.count(:world_bosses),
      event_spawn_points: Store.count(:event_spawn_points),
      # New extracted data
      quests: Store.count(:quests),
      quest_objectives: Store.count(:quest_objectives),
      quest_rewards: Store.count(:quest_rewards),
      npc_vendors: Store.count(:npc_vendors),
      gossip_entries: Store.count(:gossip_entries),
      achievements: Store.count(:achievements),
      path_missions: Store.count(:path_missions),
      challenges: Store.count(:challenges),
      world_locations: Store.count(:world_locations),
      prerequisites: Store.count(:prerequisites)
    }
  end
end
