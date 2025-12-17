defmodule BezgelorProtocol.Packets.World.ServerStoreDailyDeals do
  @moduledoc """
  Server sends today's daily deals.

  ## Wire Format
  deal_count : uint8
  deals[]    : (deal_id:u32, item_id:u32, item_name:str, original_price:u32,
                discount_percent:u8, quantity_limit:u16, quantity_sold:u16)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct deals: []

  @impl true
  def opcode, do: :server_store_daily_deals

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_u8(writer, length(packet.deals))

    writer =
      Enum.reduce(packet.deals, writer, fn deal, w ->
        w
        |> PacketWriter.write_u32(deal.id)
        |> PacketWriter.write_u32(deal.store_item.id)
        |> PacketWriter.write_wide_string(deal.store_item.name)
        |> PacketWriter.write_u32(deal.store_item.premium_price || 0)
        |> PacketWriter.write_u8(deal.discount_percent)
        |> PacketWriter.write_u16(deal.quantity_limit || 0)
        |> PacketWriter.write_u16(deal.quantity_sold)
      end)

    {:ok, writer}
  end
end
