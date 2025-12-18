defmodule BezgelorProtocol.Packets.World.ServerItemRemove do
  @moduledoc """
  Item removed from inventory.

  ## Wire Format
  container_type : uint8
  bag_index      : uint8
  slot           : uint16
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct [:container_type, :bag_index, :slot]

  @impl true
  def opcode, do: :server_item_remove

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(container_type_to_int(packet.container_type))
      |> PacketWriter.write_u8(packet.bag_index)
      |> PacketWriter.write_u16(packet.slot)

    {:ok, writer}
  end

  defp container_type_to_int(:equipped), do: 0
  defp container_type_to_int(:bag), do: 1
  defp container_type_to_int(:bank), do: 2
  defp container_type_to_int(:trade), do: 3
  defp container_type_to_int(_), do: 1
end
