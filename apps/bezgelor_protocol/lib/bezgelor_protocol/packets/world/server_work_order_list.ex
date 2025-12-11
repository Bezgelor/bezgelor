defmodule BezgelorProtocol.Packets.World.ServerWorkOrderList do
  @moduledoc """
  List of available and active work orders.

  ## Wire Format
  count          : uint8
  work_orders[]  : work_order_data (repeated)

  work_order_data:
    work_order_id      : uint32
    profession_id      : uint32
    schematic_id       : uint32
    quantity_required  : uint16
    quantity_completed : uint16
    status             : uint8   - 0 = available, 1 = active, 2 = completed
    expires_in_seconds : uint32
    reward_xp          : uint32
    reward_gold        : uint32
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct work_orders: []

  @type work_order :: %{
          work_order_id: non_neg_integer(),
          profession_id: non_neg_integer(),
          schematic_id: non_neg_integer(),
          quantity_required: non_neg_integer(),
          quantity_completed: non_neg_integer(),
          status: :available | :active | :completed,
          expires_in_seconds: non_neg_integer(),
          reward_xp: non_neg_integer(),
          reward_gold: non_neg_integer()
        }

  @type t :: %__MODULE__{work_orders: [work_order()]}

  @impl true
  def opcode, do: :server_work_order_list

  @impl true
  def write(%__MODULE__{work_orders: orders}, writer) do
    writer = PacketWriter.write_byte(writer, length(orders))

    writer =
      Enum.reduce(orders, writer, fn order, w ->
        w
        |> PacketWriter.write_uint32(order.work_order_id)
        |> PacketWriter.write_uint32(order.profession_id)
        |> PacketWriter.write_uint32(order.schematic_id)
        |> PacketWriter.write_uint16(order.quantity_required)
        |> PacketWriter.write_uint16(order.quantity_completed)
        |> PacketWriter.write_byte(status_to_int(order.status))
        |> PacketWriter.write_uint32(order.expires_in_seconds || 0)
        |> PacketWriter.write_uint32(order.reward_xp || 0)
        |> PacketWriter.write_uint32(order.reward_gold || 0)
      end)

    {:ok, writer}
  end

  defp status_to_int(:available), do: 0
  defp status_to_int(:active), do: 1
  defp status_to_int(:completed), do: 2
  defp status_to_int(_), do: 0
end
