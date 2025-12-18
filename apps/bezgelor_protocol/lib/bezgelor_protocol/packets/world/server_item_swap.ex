defmodule BezgelorProtocol.Packets.World.ServerItemSwap do
  @moduledoc """
  Server notification that two items were swapped.

  ## Wire Format
  to_item   : ItemDragDrop (item being moved TO destination)
  from_item : ItemDragDrop (item at destination being displaced)

  ## ItemDragDrop Format
  item_guid : uint64 - item GUID
  drag_drop : uint64 - encoded (location | bag_index << 8 | slot << 16)
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  import Bitwise

  defstruct [
    :item1_guid,
    :item1_location,
    :item1_bag_index,
    :item1_slot,
    :item2_guid,
    :item2_location,
    :item2_bag_index,
    :item2_slot
  ]

  @type t :: %__MODULE__{
          item1_guid: non_neg_integer(),
          item1_location: :equipped | :bag | :bank | :trade,
          item1_bag_index: non_neg_integer(),
          item1_slot: non_neg_integer(),
          item2_guid: non_neg_integer(),
          item2_location: :equipped | :bag | :bank | :trade,
          item2_bag_index: non_neg_integer(),
          item2_slot: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_item_swap

  @doc "Create a new ServerItemSwap packet."
  @spec new(map(), map()) :: t()
  def new(item1, item2) do
    %__MODULE__{
      item1_guid: item1.id,
      item1_location: item1.container_type,
      item1_bag_index: item1.bag_index,
      item1_slot: item1.slot,
      item2_guid: item2.id,
      item2_location: item2.container_type,
      item2_bag_index: item2.bag_index,
      item2_slot: item2.slot
    }
  end

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    # Write first item (moved to destination)
    drag_drop1 = encode_drag_drop(packet.item1_location, packet.item1_bag_index, packet.item1_slot)

    writer =
      writer
      |> PacketWriter.write_u64(packet.item1_guid)
      |> PacketWriter.write_u64(drag_drop1)

    # Write second item (displaced from destination)
    drag_drop2 = encode_drag_drop(packet.item2_location, packet.item2_bag_index, packet.item2_slot)

    writer =
      writer
      |> PacketWriter.write_u64(packet.item2_guid)
      |> PacketWriter.write_u64(drag_drop2)

    {:ok, writer}
  end

  # Encode location, bag_index, and slot into drag_drop format
  defp encode_drag_drop(location, bag_index, slot) do
    location_int = location_to_int(location)
    location_int ||| (bag_index <<< 8) ||| (slot <<< 16)
  end

  defp location_to_int(:equipped), do: 0
  defp location_to_int(:bag), do: 1
  defp location_to_int(:bank), do: 2
  defp location_to_int(:trade), do: 3
  defp location_to_int(_), do: 1
end
