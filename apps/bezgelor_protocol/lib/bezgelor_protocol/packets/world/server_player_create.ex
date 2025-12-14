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
            matching_flags: 0

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
          matching_flags: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_player_create

  @impl true
  @spec write(t(), PacketWriter.t()) :: {:ok, PacketWriter.t()}
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      # Empty inventory
      |> PacketWriter.write_bits(0, 32)
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
      |> PacketWriter.write_float32_bits(packet.gear_score)
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
  Create a player create packet from character data.
  """
  @spec from_character(map()) :: t()
  def from_character(character) do
    %__MODULE__{
      xp: character.total_xp || 0,
      rest_bonus_xp: character.rest_bonus_xp || 0,
      spec_index: character.active_spec || 0,
      faction_id: character.faction_id || 166,
      active_costume_index: character.active_costume_index || -1
    }
  end
end
