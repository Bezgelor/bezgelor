defmodule BezgelorProtocol.Packets.World.ServerNodeUpdate do
  @moduledoc """
  Update to a gathering node's state.

  ## Wire Format
  node_guid    : uint64
  is_available : uint8   - 1 = available, 0 = depleted
  tapped_by    : uint64  - GUID of tapping player (0 if not tapped)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:node_guid, :is_available, :tapped_by]

  @type t :: %__MODULE__{
          node_guid: non_neg_integer(),
          is_available: boolean(),
          tapped_by: non_neg_integer() | nil
        }

  @impl true
  def opcode, do: :server_node_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_uint64(packet.node_guid)
      |> PacketWriter.write_byte(if(packet.is_available, do: 1, else: 0))
      |> PacketWriter.write_uint64(packet.tapped_by || 0)

    {:ok, writer}
  end
end
