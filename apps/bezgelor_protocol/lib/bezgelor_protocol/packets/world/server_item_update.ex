defmodule BezgelorProtocol.Packets.World.ServerItemUpdate do
  @moduledoc """
  Item updated (quantity, durability, etc).

  ## Wire Format
  container_type : uint8
  bag_index      : uint8
  slot           : uint16
  quantity       : uint16
  durability     : uint8
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:container_type, :bag_index, :slot, :quantity, :durability]

  @impl true
  def opcode, do: :server_item_update

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_byte(container_type_to_int(packet.container_type))
      |> PacketWriter.write_byte(packet.bag_index)
      |> PacketWriter.write_uint16(packet.slot)
      |> PacketWriter.write_uint16(packet.quantity)
      |> PacketWriter.write_byte(packet.durability || 100)

    {:ok, writer}
  end

  defp container_type_to_int(:equipped), do: 0
  defp container_type_to_int(:bag), do: 1
  defp container_type_to_int(:bank), do: 2
  defp container_type_to_int(:trade), do: 3
  defp container_type_to_int(_), do: 1
end
