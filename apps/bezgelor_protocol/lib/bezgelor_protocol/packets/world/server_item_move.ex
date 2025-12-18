defmodule BezgelorProtocol.Packets.World.ServerItemMove do
  @moduledoc """
  Server notification that an item was moved.

  ## Wire Format (ItemDragDrop)
  item_guid : uint64 - item GUID
  drag_drop : uint64 - encoded as (location << 8) | slot

  From NexusForever: ItemLocationToDragDropData returns (location << 8 | slot)
  where slot is the BagIndex for the destination.
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  import Bitwise
  require Logger

  defstruct [:item_guid, :location, :slot]

  @type t :: %__MODULE__{
          item_guid: non_neg_integer(),
          location: :equipped | :bag | :bank | :trade,
          slot: non_neg_integer()
        }

  @impl true
  def opcode, do: :server_item_move

  @doc "Create a new ServerItemMove packet."
  @spec new(non_neg_integer(), atom(), non_neg_integer()) :: t()
  def new(item_guid, location, slot) do
    %__MODULE__{
      item_guid: item_guid,
      location: location,
      slot: slot
    }
  end

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    drag_drop = encode_drag_drop(packet.location, packet.slot)

    Logger.debug(
      "ServerItemMove: guid=#{packet.item_guid} location=#{packet.location} " <>
        "slot=#{packet.slot} drag_drop=0x#{Integer.to_string(drag_drop, 16)}"
    )

    writer =
      writer
      |> PacketWriter.write_u64(packet.item_guid)
      |> PacketWriter.write_u64(drag_drop)

    {:ok, writer}
  end

  # Encode location and slot into drag_drop format
  # Format: (location << 8) | slot - matching NexusForever's ItemLocationToDragDropData
  defp encode_drag_drop(location, slot) do
    location_int = location_to_int(location)
    (location_int <<< 8) ||| slot
  end

  defp location_to_int(:equipped), do: 0
  defp location_to_int(:bag), do: 1
  defp location_to_int(:bank), do: 2
  defp location_to_int(:trade), do: 3
  defp location_to_int(_), do: 1
end
