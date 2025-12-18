defmodule BezgelorProtocol.Packets.World.ServerWorkOrderUpdate do
  @moduledoc """
  Update to a single work order.

  ## Wire Format
  work_order_id      : uint32
  quantity_completed : uint16
  status             : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:work_order_id, :quantity_completed, :status]

  @type t :: %__MODULE__{
          work_order_id: non_neg_integer(),
          quantity_completed: non_neg_integer(),
          status: :available | :active | :completed | :expired
        }

  @impl true
  def opcode, do: :server_work_order_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u32(packet.work_order_id)
      |> PacketWriter.write_u16(packet.quantity_completed)
      |> PacketWriter.write_u8(status_to_int(packet.status))

    {:ok, writer}
  end

  defp status_to_int(:available), do: 0
  defp status_to_int(:active), do: 1
  defp status_to_int(:completed), do: 2
  defp status_to_int(:expired), do: 3
  defp status_to_int(_), do: 0
end
