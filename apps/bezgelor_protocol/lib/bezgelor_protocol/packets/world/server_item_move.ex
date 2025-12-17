defmodule BezgelorProtocol.Packets.World.ServerItemMove do
  @moduledoc """
  Server notification that an item was moved.

  ## Wire Format (ItemDragDrop)
  item_guid : uint64 - item GUID
  drag_drop : uint64 - encoded (location << 8 | bag_index), slot in high bits
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  import Bitwise

  defstruct [:item_guid, :location, :bag_index, :slot]

  @type t :: %__MODULE__{
          item_guid: non_neg_integer(),
          location: :equipped | :bag | :bank | :trade,
          bag_index: non_neg_integer(),
          slot: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_item_move

  @doc "Create a new ServerItemMove packet."
  @spec new(non_neg_integer(), atom(), non_neg_integer(), non_neg_integer()) :: t()
  def new(item_guid, location, bag_index, slot) do
    %__MODULE__{
      item_guid: item_guid,
      location: location,
      bag_index: bag_index,
      slot: slot
    }
  end

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    drag_drop = encode_drag_drop(packet.location, packet.bag_index, packet.slot)

    writer =
      writer
      |> PacketWriter.write_uint64(packet.item_guid)
      |> PacketWriter.write_uint64(drag_drop)

    {:ok, writer}
  end

  # Encode location, bag_index, and slot into drag_drop format
  # Format: location in bits 0-7, bag_index in bits 8-15, slot in bits 16+
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
