defmodule BezgelorProtocol.Packets.World.ClientVendorSell do
  @moduledoc """
  Client sells an item to a vendor.

  ## Wire Format

  ```
  location  : 9 bits (inventory location enum)
  bag_index : uint32 (slot within the bag/container)
  quantity  : uint32 (number to sell)
  ```

  Opcode: 0x0166
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  @type t :: %__MODULE__{
          location: atom(),
          bag_index: non_neg_integer(),
          quantity: non_neg_integer()
        }

  defstruct location: :inventory,
            bag_index: 0,
            quantity: 1

  # Inventory location values (matches InventoryLocation enum)
  @location_inventory 0
  @location_equipped 1
  @location_bank 2
  @location_buyback 3

  @impl true
  def opcode, do: :client_vendor_sell

  @impl true
  def read(reader) do
    with {:ok, location_int, reader} <- PacketReader.read_bits(reader, 9),
         {:ok, reader} <- {:ok, PacketReader.flush_bits(reader)},
         {:ok, bag_index, reader} <- PacketReader.read_uint32(reader),
         {:ok, quantity, reader} <- PacketReader.read_uint32(reader) do
      packet = %__MODULE__{
        location: int_to_location(location_int),
        bag_index: bag_index,
        quantity: quantity
      }

      {:ok, packet, reader}
    end
  end

  defp int_to_location(@location_inventory), do: :inventory
  defp int_to_location(@location_equipped), do: :equipped
  defp int_to_location(@location_bank), do: :bank
  defp int_to_location(@location_buyback), do: :buyback
  defp int_to_location(_), do: :inventory
end
