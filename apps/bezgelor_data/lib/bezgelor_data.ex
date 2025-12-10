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
      name = text_or_nil(item.name_text_id) || ""
      tooltip = text_or_nil(item.tooltip_text_id) || ""
      {:ok, item |> Map.put(:name, name) |> Map.put(:tooltip, tooltip)}
    end
  end

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
      texts: Store.count(:texts)
    }
  end
end
