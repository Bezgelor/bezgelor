defmodule BezgelorProtocol.Packets.World.ServerVendorItemsUpdated do
  @moduledoc """
  Sends vendor inventory to client when interacting with a vendor NPC.

  ## Wire Format

  ```
  guid                  : uint32  (vendor entity GUID)
  category_count        : uint32
  categories[]          : array of Category
  item_count            : uint32
  items[]               : array of VendorItem
  sell_price_multiplier : float   (player sells at this rate)
  buy_price_multiplier  : float   (player buys at this rate)
  unknown2              : 1 bit
  unknown3              : 1 bit
  unknown4              : 1 bit
  ```

  Category structure:
  ```
  index             : uint32
  localized_text_id : uint32
  ```

  VendorItem structure (bit-packed):
  ```
  index           : uint32
  unknown1        : 4 bits
  item_id         : uint32
  unknown3        : uint32
  unknown4        : uint32
  unknown5        : 17 bits
  unknown6        : uint32
  category_index  : uint32
  unknown8        : uint32
  unknown9        : uint64
  unknown_a       : uint32
  extra_cost1     : ExtraCost
  extra_cost2     : ExtraCost
  ```

  ExtraCost structure:
  ```
  cost_type           : 3 bits (0=none, 1=item, 2=currency, 3=account_currency)
  quantity            : uint32
  item_or_currency_id : uint32
  ```

  Opcode: 0x090B
  """
  @behaviour BezgelorProtocol.Packet.Writable

  alias BezgelorProtocol.PacketWriter

  @type extra_cost :: %{
          cost_type: :none | :item | :currency | :account_currency,
          quantity: non_neg_integer(),
          item_or_currency_id: non_neg_integer()
        }

  @type vendor_item :: %{
          index: non_neg_integer(),
          item_id: non_neg_integer(),
          category_index: non_neg_integer(),
          extra_cost1: extra_cost(),
          extra_cost2: extra_cost()
        }

  @type category :: %{
          index: non_neg_integer(),
          localized_text_id: non_neg_integer()
        }

  @type t :: %__MODULE__{
          guid: non_neg_integer(),
          categories: [category()],
          items: [vendor_item()],
          sell_price_multiplier: float(),
          buy_price_multiplier: float()
        }

  defstruct guid: 0,
            categories: [],
            items: [],
            sell_price_multiplier: 0.25,
            buy_price_multiplier: 1.0

  # Extra cost type values
  @cost_type_none 0
  @cost_type_item 1
  @cost_type_currency 2
  @cost_type_account_currency 3

  @doc "Create a new vendor items packet."
  def new(vendor_guid, items, opts \\ []) do
    %__MODULE__{
      guid: vendor_guid,
      categories: Keyword.get(opts, :categories, []),
      items: items,
      sell_price_multiplier: Keyword.get(opts, :sell_price_multiplier, 0.25),
      buy_price_multiplier: Keyword.get(opts, :buy_price_multiplier, 1.0)
    }
  end

  @doc "Create a vendor item entry."
  def vendor_item(index, item_id, opts \\ []) do
    %{
      index: index,
      item_id: item_id,
      category_index: Keyword.get(opts, :category_index, 0),
      extra_cost1: Keyword.get(opts, :extra_cost1, no_extra_cost()),
      extra_cost2: Keyword.get(opts, :extra_cost2, no_extra_cost())
    }
  end

  @doc "Create an empty extra cost."
  def no_extra_cost do
    %{cost_type: :none, quantity: 0, item_or_currency_id: 0}
  end

  @doc "Create an item extra cost (requires player to trade in items)."
  def item_cost(item_id, quantity) do
    %{cost_type: :item, quantity: quantity, item_or_currency_id: item_id}
  end

  @doc "Create a currency extra cost."
  def currency_cost(currency_type, quantity) do
    %{cost_type: :currency, quantity: quantity, item_or_currency_id: currency_type}
  end

  @impl true
  def opcode, do: :server_vendor_items_updated

  @impl true
  def write(%__MODULE__{} = packet, writer) do
    writer = PacketWriter.write_u32(writer, packet.guid)

    # Write categories
    writer = PacketWriter.write_u32(writer, length(packet.categories))
    writer = Enum.reduce(packet.categories, writer, &write_category/2)

    # Write items
    writer = PacketWriter.write_u32(writer, length(packet.items))
    writer = Enum.reduce(packet.items, writer, &write_vendor_item/2)

    # Write price multipliers and flags
    writer =
      writer
      |> PacketWriter.write_f32(packet.sell_price_multiplier)
      |> PacketWriter.write_f32(packet.buy_price_multiplier)
      |> PacketWriter.write_bits(0, 1)  # unknown2
      |> PacketWriter.write_bits(0, 1)  # unknown3
      |> PacketWriter.write_bits(0, 1)  # unknown4
      |> PacketWriter.flush_bits()

    {:ok, writer}
  end

  defp write_category(category, writer) do
    writer
    |> PacketWriter.write_u32(category.index)
    |> PacketWriter.write_u32(category.localized_text_id)
  end

  defp write_vendor_item(item, writer) do
    writer
    |> PacketWriter.write_u32(item.index)
    |> PacketWriter.write_bits(0, 4)              # unknown1
    |> PacketWriter.flush_bits()
    |> PacketWriter.write_u32(item.item_id)
    |> PacketWriter.write_u32(0)               # unknown3
    |> PacketWriter.write_u32(0)               # unknown4
    |> PacketWriter.write_bits(0, 17)             # unknown5
    |> PacketWriter.flush_bits()
    |> PacketWriter.write_u32(0)               # unknown6
    |> PacketWriter.write_u32(item.category_index)
    |> PacketWriter.write_u32(0)               # unknown8
    |> PacketWriter.write_u64(0)               # unknown9
    |> PacketWriter.write_u32(0)               # unknownA
    |> write_extra_cost(item.extra_cost1)
    |> write_extra_cost(item.extra_cost2)
  end

  defp write_extra_cost(writer, cost) do
    cost_type_value = cost_type_to_int(cost.cost_type)

    writer
    |> PacketWriter.write_bits(cost_type_value, 3)
    |> PacketWriter.flush_bits()
    |> PacketWriter.write_u32(cost.quantity)
    |> PacketWriter.write_u32(cost.item_or_currency_id)
  end

  defp cost_type_to_int(:none), do: @cost_type_none
  defp cost_type_to_int(:item), do: @cost_type_item
  defp cost_type_to_int(:currency), do: @cost_type_currency
  defp cost_type_to_int(:account_currency), do: @cost_type_account_currency
end
