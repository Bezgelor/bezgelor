defmodule BezgelorProtocol.Packets.World.ServerAbilityBook do
  @moduledoc """
  ServerAbilityBook packet (0x01A0).

  Sends the list of spells the player has learned/unlocked.
  Each spell entry contains the base spell ID, achieved tier, and spec index.

  ## Packet Structure (from NexusForever)

      u32 spell_count
      For each spell:
        u18 spell4_base_id
        u4  tier_index_achieved
        u3  spec_index

  ## Usage

      packet = %ServerAbilityBook{
        spells: [
          %{spell4_base_id: 1234, tier: 1, spec_index: 0},
          %{spell4_base_id: 5678, tier: 4, spec_index: 0}
        ]
      }
  """

  alias BezgelorProtocol.PacketWriter

  @behaviour BezgelorProtocol.Packet.Writable

  defstruct spells: []

  @type spell :: %{
          spell4_base_id: non_neg_integer(),
          tier: non_neg_integer(),
          spec_index: non_neg_integer()
        }

  @type t :: %__MODULE__{
          spells: [spell()]
        }

  @impl true
  def opcode, do: :server_ability_book

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    # Write spell count as u32
    writer = PacketWriter.write_u32(writer, length(packet.spells))

    # Write each spell entry
    writer =
      Enum.reduce(packet.spells, writer, fn spell, w ->
        w
        |> PacketWriter.write_bits(spell.spell4_base_id, 18)
        |> PacketWriter.write_bits(spell.tier, 4)
        |> PacketWriter.write_bits(spell.spec_index, 3)
      end)

    writer = PacketWriter.flush_bits(writer)
    {:ok, writer}
  end
end
