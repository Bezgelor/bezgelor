defmodule BezgelorProtocol.Packets.World.ClientStorePurchase do
  @moduledoc """
  Client request to purchase a store item.

  ## Wire Format
  item_id       : uint32
  currency_type : uint8 (0=premium, 1=bonus, 2=gold)
  promo_code    : string (length-prefixed, empty if none)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:item_id, :currency_type, :promo_code]

  @impl true
  def opcode, do: :client_store_purchase

  @impl true
  def read(reader) do
    {item_id, reader} = PacketReader.read_uint32(reader)
    {currency_byte, reader} = PacketReader.read_byte(reader)
    {promo_code, reader} = PacketReader.read_string(reader)

    packet = %__MODULE__{
      item_id: item_id,
      currency_type: currency_from_byte(currency_byte),
      promo_code: if(promo_code == "", do: nil, else: promo_code)
    }

    {:ok, packet, reader}
  end

  defp currency_from_byte(0), do: :premium
  defp currency_from_byte(1), do: :bonus
  defp currency_from_byte(2), do: :gold
  defp currency_from_byte(_), do: :premium
end
