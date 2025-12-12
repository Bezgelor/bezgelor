defmodule BezgelorProtocol.Packets.World.ClientGiftItem do
  @moduledoc """
  Client request to gift a store item to another player.

  ## Wire Format
  item_id         : uint32
  recipient_name  : string (length-prefixed)
  message         : string (length-prefixed, optional gift message)
  currency_type   : uint8 (0=premium, 1=bonus)
  """
  @behaviour BezgelorProtocol.Packet.Readable

  alias BezgelorProtocol.PacketReader

  defstruct [:item_id, :recipient_name, :message, :currency_type]

  @impl true
  def opcode, do: :client_gift_item

  @impl true
  def read(reader) do
    {item_id, reader} = PacketReader.read_uint32(reader)
    {recipient_name, reader} = PacketReader.read_string(reader)
    {message, reader} = PacketReader.read_string(reader)
    {currency_byte, reader} = PacketReader.read_byte(reader)

    packet = %__MODULE__{
      item_id: item_id,
      recipient_name: recipient_name,
      message: if(message == "", do: nil, else: message),
      currency_type: currency_from_byte(currency_byte)
    }

    {:ok, packet, reader}
  end

  defp currency_from_byte(0), do: :premium
  defp currency_from_byte(1), do: :bonus
  defp currency_from_byte(_), do: :premium
end
