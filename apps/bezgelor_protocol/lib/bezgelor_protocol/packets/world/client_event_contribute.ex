defmodule BezgelorProtocol.Packets.World.ClientEventContribute do
  @moduledoc """
  Report contribution to event objective (e.g., item turn-in).

  ## Wire Format
  instance_id     : uint32
  objective_index : uint8
  amount          : uint32
  item_id         : uint32 (0 if not item-based)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:instance_id, :objective_index, :amount, :item_id]

  @impl true
  def opcode, do: :client_event_contribute

  @impl true
  def read(reader) do
    with {:ok, instance_id, reader} <- PacketReader.read_uint32(reader),
         {:ok, objective_index, reader} <- PacketReader.read_byte(reader),
         {:ok, amount, reader} <- PacketReader.read_uint32(reader),
         {:ok, item_id, reader} <- PacketReader.read_uint32(reader) do
      {:ok,
       %__MODULE__{
         instance_id: instance_id,
         objective_index: objective_index,
         amount: amount,
         item_id: if(item_id == 0, do: nil, else: item_id)
       }, reader}
    end
  end
end
