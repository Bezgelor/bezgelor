defmodule BezgelorProtocol.Packets.World.ServerTradeskillDiscovery do
  @moduledoc """
  Notification of a new schematic/variant discovery.

  ## Wire Format
  schematic_id : uint32
  variant_id   : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:schematic_id, :variant_id]

  @type t :: %__MODULE__{
          schematic_id: non_neg_integer(),
          variant_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_tradeskill_discovery

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint32(packet.schematic_id)
      |> PacketWriter.write_uint32(packet.variant_id || 0)

    {:ok, writer}
  end
end
