defmodule BezgelorData.Store.Items do
  @moduledoc """
  Item and display-related data queries for the Store.

  Provides functions for querying item slots, visual information,
  display IDs, model paths, and character customization visuals.

  ## Display Resolution

  Items can have display IDs either directly or through ItemDisplaySource:
  - Direct: item.itemDisplayId
  - Level-scaled: item.itemSourceId -> ItemDisplaySourceEntry lookup

  ## Equipment Slots

  Items have two slot concepts:
  - ItemSlot: The visual slot type (1=ArmorChest, 20=WeaponPrimary)
  - EquippedSlot: The inventory position (0=Chest, 1=Legs, etc.)
  """

  import Bitwise

  alias BezgelorData.Store.Core
  alias BezgelorData.Store.Index

  # Item Visuals for Character Creation

  @doc """
  Get item visuals for a character based on race, sex, and customizations.

  Returns display IDs for equipment slots based on CharacterCustomizationEntry data.

  ## Parameters

  - `race` - The race ID
  - `sex` - The sex (0=male, 1=female)
  - `customizations` - List of {label_id, value} tuples

  ## Returns

  List of `%{slot: slot_id, display_id: display_id}` maps.
  """
  @spec get_item_visuals(non_neg_integer(), non_neg_integer(), [
          {non_neg_integer(), non_neg_integer()}
        ]) :: [map()]
  def get_item_visuals(race, sex, customizations) do
    race_entries = get_customizations_for_race_sex(race, sex)
    default_entries = get_customizations_for_race_sex(0, sex)
    all_entries = race_entries ++ default_entries

    custom_map = Map.new(customizations)

    all_entries
    |> Enum.filter(fn entry ->
      entry.flags == 2 && matches_customization?(entry, custom_map)
    end)
    |> Enum.map(fn entry ->
      %{slot: entry.itemSlotId, display_id: entry.itemDisplayId}
    end)
    |> Enum.uniq_by(fn %{slot: slot} -> slot end)
  end

  # Equipment Slot Functions

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
    with {:ok, item} <- Core.get(:items, item_id),
         type_id when type_id > 0 <- get_item_type_id(item),
         {:ok, item_type} <- Core.get(:item_types, type_id) do
      get_slot_id(item_type)
    else
      _ -> nil
    end
  end

  @doc """
  Get the EquippedItem slot index for an item.

  Uses the item's `equippedSlotFlags` bitmask to determine which equipped slot
  the item goes into. The lowest set bit determines the primary slot.

  ## Parameters

  - `item_id` - The item ID

  ## Returns

  The EquippedItem slot index (0=Chest, 1=Legs, 2=Head, etc.) or nil if not equippable.
  """
  @spec get_item_equipped_slot(non_neg_integer()) :: non_neg_integer() | nil
  def get_item_equipped_slot(item_id) do
    case Core.get(:items, item_id) do
      {:ok, item} ->
        flags = Map.get(item, :equippedSlotFlags, 0)

        if flags > 0 do
          find_lowest_bit(flags)
        else
          nil
        end

      _ ->
        nil
    end
  end

  # Class Gear Visuals

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
    armor_sets = Core.list(:creation_armor_sets)

    armor_set =
      Enum.find(armor_sets, fn set ->
        set_class = Map.get(set, :classId, 0)
        gear_set = Map.get(set, :creationGearSetEnum, 0)
        set_class == class_id && gear_set == 0
      end)

    if armor_set do
      slot_mapping = [
        {:itemDisplayId00, 20},
        {:itemDisplayId01, 1},
        {:itemDisplayId02, 2},
        {:itemDisplayId03, 3},
        {:itemDisplayId04, 4},
        {:itemDisplayId05, 5},
        {:itemDisplayId06, 6}
      ]

      slot_mapping
      |> Enum.map(fn {key, slot} ->
        display_id = Map.get(armor_set, key, 0)
        if display_id > 0, do: %{slot: slot, display_id: display_id}, else: nil
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  # Display ID Resolution

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
  """
  @spec get_item_display_id(non_neg_integer(), non_neg_integer() | nil) :: non_neg_integer()
  def get_item_display_id(item_id, power_level \\ nil) do
    case Core.get(:items, item_id) do
      {:ok, item} ->
        item_source_id = Map.get(item, :itemSourceId) || 0
        display_id = Map.get(item, :itemDisplayId) || 0
        item_power_level = power_level || Map.get(item, :powerLevel) || 0
        type_id = Map.get(item, :item2TypeId) || 0

        if item_source_id > 0 do
          resolve_display_from_source(item_source_id, type_id, item_power_level, display_id)
        else
          display_id
        end

      :error ->
        0
    end
  end

  @doc """
  Get the display ID and visual slot for an item.

  Returns {display_id, visual_slot} where visual_slot comes from Item2Type.itemSlotId.
  This is used for building ItemVisual structs for entity creation.
  """
  @spec get_item_visual_info(non_neg_integer(), non_neg_integer() | nil) ::
          {non_neg_integer(), non_neg_integer()}
  def get_item_visual_info(item_id, power_level \\ nil) do
    case Core.get(:items, item_id) do
      {:ok, item} ->
        display_id = get_item_display_id(item_id, power_level)
        type_id = Map.get(item, :item2TypeId) || 0
        visual_slot = get_item_slot_id(type_id)
        {display_id, visual_slot}

      :error ->
        {0, 0}
    end
  end

  # Model Path Functions

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
  """
  @spec get_display_model_path(non_neg_integer()) :: map() | nil
  def get_display_model_path(display_id) when is_integer(display_id) and display_id > 0 do
    case :ets.lookup(Core.table_name(:item_displays), display_id) do
      [{^display_id, display}] ->
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

  # Item with Name

  @doc """
  Get an item with its localized name resolved.

  Looks up the item and adds a `:name` field with the localized text.

  ## Parameters

  - `item_id` - The item ID

  ## Returns

  `{:ok, item_map_with_name}` or `:error` if not found.

  ## Example

      {:ok, item} = Store.get_item_with_name(12345)
      item.name #=> "Iron Sword"
  """
  @spec get_item_with_name(non_neg_integer()) :: {:ok, map()} | :error
  def get_item_with_name(item_id) do
    case Core.get(:items, item_id) do
      {:ok, item} -> {:ok, add_item_name(item)}
      :error -> :error
    end
  end

  # Private helpers

  defp get_item_type_id(item) do
    Map.get(item, :item2TypeId, 0)
  end

  defp get_slot_id(item_type) do
    Map.get(item_type, :itemSlotId, 0)
  end

  defp find_lowest_bit(flags) when flags > 0 do
    do_find_lowest_bit(flags, 0)
  end

  defp find_lowest_bit(_), do: nil

  defp do_find_lowest_bit(flags, position) when position < 32 do
    if band(flags, 1) == 1 do
      position
    else
      do_find_lowest_bit(bsr(flags, 1), position + 1)
    end
  end

  defp do_find_lowest_bit(_, _), do: nil

  defp get_item_slot_id(type_id) when type_id > 0 do
    case Core.get(:item_types, type_id) do
      {:ok, item_type} ->
        Map.get(item_type, :itemSlotId) || 0

      :error ->
        0
    end
  end

  defp get_item_slot_id(_), do: 0

  defp resolve_display_from_source(source_id, type_id, power_level, fallback_display_id) do
    entries = get_display_source_entries(source_id)

    matching_entries =
      Enum.filter(entries, fn entry ->
        entry_type_id = Map.get(entry, :item2TypeId) || 0
        entry_type_id == type_id
      end)

    case matching_entries do
      [] ->
        fallback_display_id

      [single] ->
        Map.get(single, :itemDisplayId) || fallback_display_id

      multiple when is_list(multiple) ->
        if fallback_display_id > 0 do
          fallback_display_id
        else
          level_match =
            Enum.find(multiple, fn entry ->
              min_level = Map.get(entry, :itemMinLevel) || 0
              max_level = Map.get(entry, :itemMaxLevel) || 999
              power_level >= min_level and power_level <= max_level
            end)

          if level_match do
            Map.get(level_match, :itemDisplayId) || fallback_display_id
          else
            fallback_display_id
          end
        end
    end
  end

  defp get_display_source_entries(source_id) do
    Index.lookup_index(:display_sources_by_source_id, source_id)
  end

  defp get_display_field(display, field) when is_atom(field) do
    value = Map.get(display, field) || Map.get(display, Atom.to_string(field))
    if value == "", do: nil, else: value
  end

  defp get_item_field(item, field) when is_atom(field) do
    Map.get(item, field) || Map.get(item, Atom.to_string(field))
  end

  defp add_item_name(item) do
    name = get_item_name(item)
    item_id = Map.get(item, :ID) || Map.get(item, :id, 0)
    Map.put(item, :name, name || "Item ##{item_id}")
  end

  defp get_item_name(item) do
    text_id =
      get_item_field(item, :name_text_id) ||
        Map.get(item, :localizedTextIdName) ||
        0

    if text_id > 0 do
      BezgelorData.Store.get_text(text_id)
    else
      nil
    end
  end

  defp matches_customization?(entry, custom_map) do
    label0 = entry.characterCustomizationLabelId00
    value0 = entry.value00
    label1 = entry.characterCustomizationLabelId01
    value1 = entry.value01

    match0 = label0 == 0 || Map.get(custom_map, label0) == value0
    match1 = label1 == 0 || Map.get(custom_map, label1) == value1

    match0 && match1 && (label0 != 0 || label1 != 0)
  end

  defp get_customizations_for_race_sex(race, sex) do
    Index.lookup_index(:customizations_by_race_sex, {race, sex})
  end
end
