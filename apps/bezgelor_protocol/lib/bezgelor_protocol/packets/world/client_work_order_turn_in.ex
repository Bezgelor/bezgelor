defmodule BezgelorProtocol.Packets.World.ClientWorkOrderTurnIn do
  @moduledoc """
  Client request to turn in a completed work order.

  ## Wire Format
  work_order_id : uint32  - Work order to turn in
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:work_order_id]

  @type t :: %__MODULE__{
          work_order_id: non_neg_integer()
        }

  @impl true
  def opcode, do: :client_work_order_turn_in

  @impl true
  def read(reader) do
    with {:ok, work_order_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok, %__MODULE__{work_order_id: work_order_id}, reader}
    end
  end
end
