defmodule BezgelorProtocol.Packets.World.ServerAmpList do
  @moduledoc """
  ServerAmpList packet (0x019E).

  Sends the list of Eldan Augmentations (AMPs) for a spec.
  AMPs are passive skill tree nodes that enhance abilities.

  ## Packet Structure (from NexusForever)

      u3  spec_index    # Which spec (0-3)
      u7  amp_count     # Number of AMPs
      For each AMP:
        u16 amp_id      # EldanAugmentationId

  ## Usage

      packet = %ServerAmpList{
        spec_index: 0,
        amps: []  # Empty for new characters
      }
  """

  alias BezgelorProtocol.PacketWriter

  @behaviour BezgelorProtocol.Packet.Writable

  defstruct spec_index: 0, amps: []

  @type t :: %__MODULE__{
          spec_index: non_neg_integer(),
          amps: [non_neg_integer()]
        }

  @impl true
  def opcode, do: :server_amp_list

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_bits(packet.spec_index, 3)
      |> PacketWriter.write_bits(length(packet.amps), 7)

    # Write each AMP ID (u16)
    writer =
      Enum.reduce(packet.amps, writer, fn amp_id, w ->
        PacketWriter.write_u16(w, amp_id)
      end)

    writer = PacketWriter.flush_bits(writer)
    {:ok, writer}
  end
end
