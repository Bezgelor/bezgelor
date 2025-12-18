defmodule BezgelorProtocol.Packets.World.ServerGenericError do
  @moduledoc """
  Server notification of a generic error.

  Sent when an operation fails (item move, vendor interaction, etc.).

  ## Wire Format
  error: 8 bits (GenericError enum)

  ## Common Error Codes (from NexusForever)
  - 0x001B (27) - ItemInventoryFull
  - 0x001C (28) - ItemUnknownItem
  - 0x001F (31) - ItemNotValidForSlot
  - 0x0020 (32) - ItemLocked
  - 0x0023 (35) - ItemBagMustBeEmpty
  """

  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct error: 0

  @type t :: %__MODULE__{
          error: non_neg_integer()
        }

  # Common error codes
  @item_inventory_full 0x001B
  @item_unknown_item 0x001C
  @item_not_valid_for_slot 0x001F
  @item_locked 0x0020
  @item_bag_must_be_empty 0x0023
  @slot_occupied 0x001F

  @doc "Error code for inventory full"
  def item_inventory_full, do: @item_inventory_full

  @doc "Error code for unknown item"
  def item_unknown_item, do: @item_unknown_item

  @doc "Error code for item not valid for slot"
  def item_not_valid_for_slot, do: @item_not_valid_for_slot

  @doc "Error code for locked item"
  def item_locked, do: @item_locked

  @doc "Error code for bag must be empty"
  def item_bag_must_be_empty, do: @item_bag_must_be_empty

  @doc "Error code for slot occupied (same as not_valid_for_slot)"
  def slot_occupied, do: @slot_occupied

  @impl true
  def opcode, do: :server_generic_error

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer =
      writer
      |> PacketWriter.write_u8(packet.error)
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end
end
