defmodule BezgelorProtocol.Packets.World.ServerVendorItemsUpdatedTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerVendorItemsUpdated
  alias BezgelorProtocol.PacketWriter

  describe "new/3" do
    test "creates packet with default multipliers" do
      items = [ServerVendorItemsUpdated.vendor_item(0, 1234)]
      packet = ServerVendorItemsUpdated.new(100, items)

      assert packet.guid == 100
      assert packet.sell_price_multiplier == 0.25
      assert packet.buy_price_multiplier == 1.0
      assert length(packet.items) == 1
    end

    test "creates packet with custom multipliers" do
      items = []
      packet = ServerVendorItemsUpdated.new(100, items,
        sell_price_multiplier: 0.5,
        buy_price_multiplier: 0.75
      )

      assert packet.sell_price_multiplier == 0.5
      assert packet.buy_price_multiplier == 0.75
    end
  end

  describe "vendor_item/3" do
    test "creates item with defaults" do
      item = ServerVendorItemsUpdated.vendor_item(0, 5678)

      assert item.index == 0
      assert item.item_id == 5678
      assert item.category_index == 0
      assert item.extra_cost1.cost_type == :none
      assert item.extra_cost2.cost_type == :none
    end

    test "creates item with category" do
      item = ServerVendorItemsUpdated.vendor_item(1, 5678, category_index: 2)

      assert item.category_index == 2
    end

    test "creates item with extra cost" do
      extra = ServerVendorItemsUpdated.item_cost(9999, 5)
      item = ServerVendorItemsUpdated.vendor_item(0, 5678, extra_cost1: extra)

      assert item.extra_cost1.cost_type == :item
      assert item.extra_cost1.quantity == 5
      assert item.extra_cost1.item_or_currency_id == 9999
    end
  end

  describe "extra cost helpers" do
    test "no_extra_cost returns empty cost" do
      cost = ServerVendorItemsUpdated.no_extra_cost()

      assert cost.cost_type == :none
      assert cost.quantity == 0
      assert cost.item_or_currency_id == 0
    end

    test "item_cost creates item trade requirement" do
      cost = ServerVendorItemsUpdated.item_cost(1001, 10)

      assert cost.cost_type == :item
      assert cost.quantity == 10
      assert cost.item_or_currency_id == 1001
    end

    test "currency_cost creates currency requirement" do
      cost = ServerVendorItemsUpdated.currency_cost(2, 500)

      assert cost.cost_type == :currency
      assert cost.quantity == 500
      assert cost.item_or_currency_id == 2
    end
  end

  describe "write/2" do
    test "writes empty vendor packet" do
      packet = ServerVendorItemsUpdated.new(42, [])
      writer = PacketWriter.new()

      {:ok, writer} = ServerVendorItemsUpdated.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Parse the binary
      <<
        guid::little-32,
        category_count::little-32,
        item_count::little-32,
        _rest::binary
      >> = binary

      assert guid == 42
      assert category_count == 0
      assert item_count == 0
    end

    test "writes vendor packet with items" do
      items = [
        ServerVendorItemsUpdated.vendor_item(0, 1234),
        ServerVendorItemsUpdated.vendor_item(1, 5678)
      ]
      packet = ServerVendorItemsUpdated.new(100, items)
      writer = PacketWriter.new()

      {:ok, writer} = ServerVendorItemsUpdated.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Parse header
      <<
        guid::little-32,
        category_count::little-32,
        item_count::little-32,
        _items::binary
      >> = binary

      assert guid == 100
      assert category_count == 0
      assert item_count == 2
    end

    test "writes categories" do
      categories = [
        %{index: 0, localized_text_id: 12345},
        %{index: 1, localized_text_id: 67890}
      ]
      packet = ServerVendorItemsUpdated.new(100, [], categories: categories)
      writer = PacketWriter.new()

      {:ok, writer} = ServerVendorItemsUpdated.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<
        _guid::little-32,
        category_count::little-32,
        cat1_index::little-32,
        cat1_text::little-32,
        cat2_index::little-32,
        cat2_text::little-32,
        _rest::binary
      >> = binary

      assert category_count == 2
      assert cat1_index == 0
      assert cat1_text == 12345
      assert cat2_index == 1
      assert cat2_text == 67890
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerVendorItemsUpdated.opcode() == :server_vendor_items_updated
    end
  end
end
