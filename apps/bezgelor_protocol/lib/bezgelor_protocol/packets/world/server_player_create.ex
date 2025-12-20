defmodule BezgelorProtocol.Packets.World.ServerPlayerCreate do
  @moduledoc """
  Server packet with full player data sent after world entry.

  This is the main packet containing all player state:
  - Inventory items
  - Money (16 currency types)
  - XP and rest bonus
  - Faction data
  - Pets, costumes, dyes
  - Tradeskill materials
  - Character entitlements

  ## Wire Format (from NexusForever)

  ```
  inventory_count     : uint32
  inventory[]         : InventoryItem (complex)
  money[16]           : uint64[16] - currencies
  xp                  : uint32
  rest_bonus_xp       : uint32
  item_proficiencies  : 32 bits
  elder_points        : uint32
  daily_elder_points  : uint32
  spec_index          : 3 bits
  bonus_power         : uint16
  unknown_a0          : uint32
  faction_data        : Faction struct
  pets_count          : uint32
  pets[]              : Pet struct
  input_key_set       : uint32
  unknown_bc          : uint16
  active_costume_idx  : int32 (signed)
  unknown_c4          : uint32
  unknown_c8          : uint32
  known_dyes_count    : 6 bits
  known_dyes[]        : uint16
  tradeskill_mats[512]: uint16[512]
  gear_score          : float32
  is_pvp_server       : bool
  matching_flags      : uint32
  entitlements_count  : uint32
  entitlements[]      : CharacterEntitlement struct
  ```
  """

  @behaviour BezgelorProtocol.Packet.Writable

  import Bitwise

  alias BezgelorProtocol.PacketWriter

  defstruct xp: 0,
            rest_bonus_xp: 0,
            item_proficiencies: 0,
            elder_points: 0,
            daily_elder_points: 0,
            spec_index: 0,
            bonus_power: 0,
            faction_id: 166,
            active_costume_index: -1,
            input_key_set: 0,
            gear_score: 0.0,
            is_pvp_server: false,
            matching_flags: 0,
            inventory: []

  @type t :: %__MODULE__{
          xp: non_neg_integer(),
          rest_bonus_xp: non_neg_integer(),
          item_proficiencies: non_neg_integer(),
          elder_points: non_neg_integer(),
          daily_elder_points: non_neg_integer(),
          spec_index: non_neg_integer(),
          bonus_power: non_neg_integer(),
          faction_id: non_neg_integer(),
          active_costume_index: integer(),
          input_key_set: non_neg_integer(),
          gear_score: float(),
          is_pvp_server: boolean(),
          matching_flags: non_neg_integer(),
          inventory: list()
        }

  # InventoryLocation enum values
  @location_equipped 0
  @location_inventory 1
  @location_bank 2

  # ItemUpdateReason enum (6 bits)
  @reason_no_reason 0

  @impl true
  def opcode, do: :server_player_create

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      # Inventory count and items
      |> PacketWriter.write_u32(length(packet.inventory))
      |> write_inventory_items(packet.inventory)
      # Money[16] - 16 uint64 currencies (all zero)
      |> write_money()
      # XP
      |> PacketWriter.write_bits(packet.xp, 32)
      # Rest bonus XP
      |> PacketWriter.write_bits(packet.rest_bonus_xp, 32)
      # Item proficiencies
      |> PacketWriter.write_bits(packet.item_proficiencies, 32)
      # Elder points
      |> PacketWriter.write_bits(packet.elder_points, 32)
      # Daily elder points
      |> PacketWriter.write_bits(packet.daily_elder_points, 32)
      # Spec index (3 bits)
      |> PacketWriter.write_bits(packet.spec_index, 3)
      # Bonus power (uint16)
      |> PacketWriter.write_bits(packet.bonus_power, 16)
      # Unknown A0
      |> PacketWriter.write_bits(0, 32)
      # Faction data: faction_id (14 bits) + reputation count (uint16)
      |> PacketWriter.write_bits(packet.faction_id, 14)
      |> PacketWriter.write_bits(0, 16)
      # Pets count
      |> PacketWriter.write_bits(0, 32)
      # Input key set
      |> PacketWriter.write_bits(packet.input_key_set, 32)
      # Unknown BC (uint16)
      |> PacketWriter.write_bits(0, 16)
      # Active costume index (int32 - signed, -1 = none)
      |> write_signed_int32(packet.active_costume_index)
      # Unknown C4
      |> PacketWriter.write_bits(0, 32)
      # Unknown C8
      |> PacketWriter.write_bits(0, 32)
      # Known dyes count (6 bits)
      |> PacketWriter.write_bits(0, 6)
      # Tradeskill materials[512] - all zeros
      |> write_tradeskill_materials()
      # Gear score (float)
      |> PacketWriter.write_f32(packet.gear_score)
      # Is PvP server (bool)
      |> PacketWriter.write_bits(if(packet.is_pvp_server, do: 1, else: 0), 1)
      # Matching eligibility flags
      |> PacketWriter.write_bits(packet.matching_flags, 32)
      # Character entitlements count
      |> PacketWriter.write_bits(0, 32)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  # Write 16 uint64 values for money (all zero)
  defp write_money(writer) do
    Enum.reduce(1..16, writer, fn _i, w ->
      PacketWriter.write_bits(w, 0, 64)
    end)
  end

  # Write 512 uint16 values for tradeskill materials (all zero)
  defp write_tradeskill_materials(writer) do
    Enum.reduce(1..512, writer, fn _i, w ->
      PacketWriter.write_bits(w, 0, 16)
    end)
  end

  # Write signed int32 using two's complement
  defp write_signed_int32(writer, value) when value < 0 do
    # Two's complement for negative numbers
    unsigned = :erlang.band(value, 0xFFFFFFFF)
    PacketWriter.write_bits(writer, unsigned, 32)
  end

  defp write_signed_int32(writer, value) do
    PacketWriter.write_bits(writer, value, 32)
  end

  @doc """
  Create a player create packet from character data and inventory.
  """
  @spec from_character(map(), list()) :: t()
  def from_character(character, inventory \\ []) do
    %__MODULE__{
      xp: character.total_xp || 0,
      rest_bonus_xp: character.rest_bonus_xp || 0,
      item_proficiencies: get_class_proficiencies(character.class),
      spec_index: character.active_spec || 0,
      faction_id: character.faction_id || 166,
      active_costume_index: character.active_costume_index || -1,
      inventory: inventory
    }
  end

  # Item proficiency flags from NexusForever ItemProficiency enum
  @proficiency_heavy_armor 0x000002
  @proficiency_medium_armor 0x000004
  @proficiency_light_armor 0x000008
  @proficiency_great_weapon 0x000010
  @proficiency_heavy_gun 0x000040
  @proficiency_resonators 0x000100
  @proficiency_pistols 0x001000
  @proficiency_psyblade 0x040000
  @proficiency_claws 0x100000

  # Get item proficiencies bitmask based on class
  # Class IDs: 1=Warrior, 2=Engineer, 3=Esper, 4=Medic, 5=Stalker, 7=Spellslinger
  defp get_class_proficiencies(1), do: @proficiency_heavy_armor ||| @proficiency_great_weapon
  defp get_class_proficiencies(2), do: @proficiency_heavy_armor ||| @proficiency_heavy_gun
  defp get_class_proficiencies(3), do: @proficiency_light_armor ||| @proficiency_psyblade
  defp get_class_proficiencies(4), do: @proficiency_medium_armor ||| @proficiency_resonators
  defp get_class_proficiencies(5), do: @proficiency_medium_armor ||| @proficiency_claws
  defp get_class_proficiencies(7), do: @proficiency_light_armor ||| @proficiency_pistols
  # Default: allow all armor types if class unknown
  defp get_class_proficiencies(_),
    do: @proficiency_heavy_armor ||| @proficiency_medium_armor ||| @proficiency_light_armor

  # Write all inventory items
  defp write_inventory_items(writer, []), do: writer

  defp write_inventory_items(writer, [item | rest]) do
    writer
    |> write_inventory_item(item)
    |> write_inventory_items(rest)
  end

  # Write a single inventory item (InventoryItem = Item + 6-bit reason)
  defp write_inventory_item(writer, item) do
    require Logger
    # Generate guid from item ID or use database ID
    guid = item[:id] || generate_item_guid(item)

    bag_index = inventory_bag_index(item)

    Logger.debug(
      "WriteItem: guid=#{guid} item_id=#{item[:item_id]} location=#{item[:container_type]} " <>
        "bag_index=#{bag_index} slot=#{item[:slot]}"
    )

    writer
    # Item guid (uint64)
    |> PacketWriter.write_u64(guid)
    # Unknown0 (uint64)
    |> PacketWriter.write_u64(0)
    # Item ID (18 bits)
    |> PacketWriter.write_bits(item[:item_id] || 0, 18)
    # Location (9 bits)
    |> PacketWriter.write_bits(location_to_int(item[:container_type]), 9)
    # Bag index (uint32) - use bag_index for bags/ability, slot for equipped
    |> PacketWriter.write_u32(bag_index)
    # Stack count (uint32)
    |> PacketWriter.write_u32(item[:quantity] || 1)
    # Charges (uint32)
    |> PacketWriter.write_u32(item[:charges] || 0)
    # Random circuit data (uint64)
    |> PacketWriter.write_u64(0)
    # Random glyph data (uint32)
    |> PacketWriter.write_u32(0)
    # Threshold data (uint64)
    |> PacketWriter.write_u64(0)
    # Durability (float32)
    |> PacketWriter.write_f32(normalize_durability(item[:durability]))
    # Unknown44 (uint32)
    |> PacketWriter.write_u32(0)
    # Unknown48 (uint8)
    |> PacketWriter.write_u8(0)
    # Dye data (uint32)
    |> PacketWriter.write_u32(0)
    # Dynamic flags (uint32)
    |> PacketWriter.write_u32(0)
    # Expiration time left (uint32)
    |> PacketWriter.write_u32(0)
    # Unknown58 array (2 elements, each 3-bit + uint32 + uint32)
    |> write_unknown58_entry()
    |> write_unknown58_entry()
    # Unknown70 (18 bits)
    |> PacketWriter.write_bits(0, 18)
    # Microchips count (3 bits) + array
    |> PacketWriter.write_bits(0, 3)
    # Glyphs count (4 bits) + array
    |> PacketWriter.write_bits(0, 4)
    # Unknown88 count (6 bits) + array
    |> PacketWriter.write_bits(0, 6)
    # Effective item level (uint32)
    |> PacketWriter.write_u32(0)
    # ItemUpdateReason (6 bits)
    |> PacketWriter.write_bits(@reason_no_reason, 6)
  end

  # Write an Unknown58 entry (3-bit + uint32 + uint32)
  defp write_unknown58_entry(writer) do
    writer
    |> PacketWriter.write_bits(0, 3)
    |> PacketWriter.write_u32(0)
    |> PacketWriter.write_u32(0)
  end

  # Convert durability (0-100) to float 0.0-1.0
  defp normalize_durability(nil), do: 1.0
  defp normalize_durability(d) when is_float(d) and d <= 1.0, do: d
  defp normalize_durability(d) when is_integer(d), do: d / 100.0
  defp normalize_durability(d) when is_float(d), do: d / 100.0

  defp location_to_int(:equipped), do: @location_equipped
  defp location_to_int(:inventory), do: @location_inventory
  defp location_to_int(:bag), do: @location_inventory
  defp location_to_int(:bank), do: @location_bank
  defp location_to_int(loc) when is_integer(loc), do: loc
  defp location_to_int(_), do: @location_inventory

  # Determine bag index based on container type
  defp inventory_bag_index(item) do
    case item[:container_type] do
      :equipped -> item[:slot] || 0
      _ -> item[:bag_index] || item[:slot] || 0
    end
  end

  # Generate a unique item guid from location and slot
  defp generate_item_guid(item) do
    container_int = location_to_int(item[:container_type])
    container_int <<< 32 ||| inventory_bag_index(item)
  end
end
