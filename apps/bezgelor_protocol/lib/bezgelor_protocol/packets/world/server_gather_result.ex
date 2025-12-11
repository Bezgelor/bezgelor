defmodule BezgelorProtocol.Packets.World.ServerGatherResult do
  @moduledoc """
  Result of gathering from a node.

  ## Wire Format
  result      : uint8   - 0 = success, 1 = failed, 2 = node_depleted
  node_guid   : uint64
  item_count  : uint8
  items[]     : item_data (repeated)
  xp_gained   : uint32

  item_data:
    item_id  : uint32
    quantity : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:result, :node_guid, :items, :xp_gained]

  @type item :: %{item_id: non_neg_integer(), quantity: non_neg_integer()}
  @type result :: :success | :failed | :node_depleted

  @type t :: %__MODULE__{
          result: result(),
          node_guid: non_neg_integer(),
          items: [item()],
          xp_gained: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_gather_result

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    items = packet.items || []

    writer =
      writer
      |> PacketWriter.write_byte(result_to_int(packet.result))
      |> PacketWriter.write_uint64(packet.node_guid)
      |> PacketWriter.write_byte(length(items))

    writer =
      Enum.reduce(items, writer, fn item, w ->
        w
        |> PacketWriter.write_uint32(item.item_id)
        |> PacketWriter.write_uint16(item.quantity)
      end)

    writer = PacketWriter.write_uint32(writer, packet.xp_gained || 0)

    {:ok, writer}
  end

  defp result_to_int(:success), do: 0
  defp result_to_int(:failed), do: 1
  defp result_to_int(:node_depleted), do: 2
  defp result_to_int(_), do: 0
end
