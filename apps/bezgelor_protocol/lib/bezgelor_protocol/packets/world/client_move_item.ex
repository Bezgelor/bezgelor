defmodule BezgelorProtocol.Packets.World.ClientMoveItem do
  @moduledoc """
  Client request to move an item.

  ## Wire Format
  src_container  : uint8
  src_bag_index  : uint8
  src_slot       : uint16
  dst_container  : uint8
  dst_bag_index  : uint8
  dst_slot       : uint16
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:src_container, :src_bag_index, :src_slot, :dst_container, :dst_bag_index, :dst_slot]

  @impl true
  def opcode, do: :client_move_item

  @impl true
  def read(reader) do
    with {:ok, src_container, reader} <- PacketReader.read_byte(reader),
         {:ok, src_bag_index, reader} <- PacketReader.read_byte(reader),
         {:ok, src_slot, reader} <- PacketReader.read_uint16(reader),
         {:ok, dst_container, reader} <- PacketReader.read_byte(reader),
         {:ok, dst_bag_index, reader} <- PacketReader.read_byte(reader),
         {:ok, dst_slot, reader} <- PacketReader.read_uint16(reader) do
      packet = %__MODULE__{
        src_container: int_to_container_type(src_container),
        src_bag_index: src_bag_index,
        src_slot: src_slot,
        dst_container: int_to_container_type(dst_container),
        dst_bag_index: dst_bag_index,
        dst_slot: dst_slot
      }

      {:ok, packet, reader}
    end
  end

  defp int_to_container_type(0), do: :equipped
  defp int_to_container_type(1), do: :bag
  defp int_to_container_type(2), do: :bank
  defp int_to_container_type(3), do: :trade
  defp int_to_container_type(_), do: :bag
end
