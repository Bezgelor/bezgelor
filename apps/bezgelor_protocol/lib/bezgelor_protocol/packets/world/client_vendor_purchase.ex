defmodule BezgelorProtocol.Packets.World.ClientVendorPurchase do
  @moduledoc """
  Client requests to purchase item(s) from a vendor.

  ## Wire Format

  ```
  vendor_index : uint32 (index in the vendor's item list)
  quantity     : uint32 (number of items to buy)
  ```

  Opcode: 0x00BE
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  @type t :: %__MODULE__{
          vendor_index: non_neg_integer(),
          quantity: non_neg_integer()
        }

  defstruct vendor_index: 0,
            quantity: 1

  @impl true
  def opcode, do: :client_vendor_purchase

  @impl true
  def read(reader) do
    with {:ok, vendor_index, reader} <- PacketReader.read_uint32(reader),
         {:ok, quantity, reader} <- PacketReader.read_uint32(reader) do
      packet = %__MODULE__{
        vendor_index: vendor_index,
        quantity: quantity
      }

      {:ok, packet, reader}
    end
  end
end
