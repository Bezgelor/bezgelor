defmodule BezgelorProtocol.Packets.World.ServerStoreCatalog do
  @moduledoc """
  Server response with store catalog.

  ## Wire Format
  category_count : uint16
  categories[]   : (id:u32, name:str, parent_id:u32, icon:str)
  item_count     : uint16
  items[]        : (id:u32, type:str, item_id:u32, name:str, desc:str,
                    premium:u32, bonus:u32, gold:u64, cat_id:u32, featured:u8,
                    sale_price:u32, sale_ends:u64, new:u8)
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  defstruct categories: [], items: []

  @impl true
  def opcode, do: :server_store_catalog

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    # Write categories
    writer = PacketWriter.write_u16(writer, length(packet.categories))

    writer =
      Enum.reduce(packet.categories, writer, fn cat, w ->
        w
        |> PacketWriter.write_u32(cat.id)
        |> PacketWriter.write_wide_string(cat.name)
        |> PacketWriter.write_u32(cat.parent_id || 0)
        |> PacketWriter.write_wide_string(cat.icon || "")
      end)

    # Write items
    writer = PacketWriter.write_u16(writer, length(packet.items))

    writer =
      Enum.reduce(packet.items, writer, fn item, w ->
        w
        |> PacketWriter.write_u32(item.id)
        |> PacketWriter.write_wide_string(item.item_type)
        |> PacketWriter.write_u32(item.item_id)
        |> PacketWriter.write_wide_string(item.name)
        |> PacketWriter.write_wide_string(item.description || "")
        |> PacketWriter.write_u32(item.premium_price || 0)
        |> PacketWriter.write_u32(item.bonus_price || 0)
        |> PacketWriter.write_u64(item.gold_price || 0)
        |> PacketWriter.write_u32(item.category_id || 0)
        |> PacketWriter.write_u8(if(item.featured, do: 1, else: 0))
        |> PacketWriter.write_u32(item.sale_price || 0)
        |> PacketWriter.write_u64(datetime_to_unix(item.sale_ends_at))
        |> PacketWriter.write_u8(if(item.is_new, do: 1, else: 0))
      end)

    {:ok, writer}
  end

  defp datetime_to_unix(nil), do: 0
  defp datetime_to_unix(%DateTime{} = dt), do: DateTime.to_unix(dt)
end
