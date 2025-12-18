defmodule BezgelorProtocol.Packets.World.ServerInventoryList do
  @moduledoc """
  Full inventory list sent to client on login.

  ## Wire Format
  bag_count   : uint8
  bags        : [BagEntry] * bag_count
  item_count  : uint16
  items       : [ItemEntry] * item_count

  BagEntry:
    bag_index : uint8
    item_id   : uint32
    size      : uint8

  ItemEntry:
    container_type : uint8 (0=equipped, 1=bag, 2=bank, 3=trade)
    bag_index      : uint8
    slot           : uint16
    item_id        : uint32
    quantity       : uint16
    durability     : uint8
    bound          : uint8 (bool)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct bags: [], items: []

  @impl true
  def opcode, do: :server_inventory_list

  @impl true
  def write(%__MODULE__{bags: bags, items: items}, writer) do
    # Write bags
    writer = PacketWriter.write_u8(writer, length(bags))

    writer =
      Enum.reduce(bags, writer, fn bag, w ->
        w
        |> PacketWriter.write_u8(bag.bag_index)
        |> PacketWriter.write_u32(bag.item_id || 0)
        |> PacketWriter.write_u8(bag.size)
      end)

    # Write items
    writer = PacketWriter.write_u16(writer, length(items))

    writer =
      Enum.reduce(items, writer, fn item, w ->
        w
        |> PacketWriter.write_u8(container_type_to_int(item.container_type))
        |> PacketWriter.write_u8(item.bag_index)
        |> PacketWriter.write_u16(item.slot)
        |> PacketWriter.write_u32(item.item_id)
        |> PacketWriter.write_u16(item.quantity)
        |> PacketWriter.write_u8(item.durability || 100)
        |> PacketWriter.write_u8(if(item.bound, do: 1, else: 0))
      end)

    {:ok, writer}
  end

  defp container_type_to_int(:equipped), do: 0
  defp container_type_to_int(:bag), do: 1
  defp container_type_to_int(:bank), do: 2
  defp container_type_to_int(:trade), do: 3
  defp container_type_to_int(_), do: 1
end
