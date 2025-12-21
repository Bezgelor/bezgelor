defmodule BezgelorProtocol.Packets.World.ServerItemSwapTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerItemSwap
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "encodes item swap between bag slots" do
      packet = %ServerItemSwap{
        item1_guid: 100,
        item1_location: :bag,
        item1_bag_index: 0,
        item1_slot: 5,
        item2_guid: 200,
        item2_location: :bag,
        item2_bag_index: 0,
        item2_slot: 10
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerItemSwap.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # 16 bytes per ItemDragDrop x 2 = 32 bytes
      assert byte_size(binary) == 32

      <<
        item1_guid::little-64,
        drag_drop1::little-64,
        item2_guid::little-64,
        drag_drop2::little-64
      >> = binary

      assert item1_guid == 100
      assert item2_guid == 200

      # Decode drag_drop1
      # :bag
      assert Bitwise.band(drag_drop1, 0xFF) == 1
      # slot
      assert Bitwise.bsr(drag_drop1, 16) == 5

      # Decode drag_drop2
      # :bag
      assert Bitwise.band(drag_drop2, 0xFF) == 1
      # slot
      assert Bitwise.bsr(drag_drop2, 16) == 10
    end

    test "encodes swap between equipped and bag" do
      packet = %ServerItemSwap{
        item1_guid: 111,
        item1_location: :equipped,
        item1_bag_index: 0,
        # e.g., chest slot
        item1_slot: 2,
        item2_guid: 222,
        item2_location: :bag,
        item2_bag_index: 0,
        item2_slot: 0
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerItemSwap.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<
        _item1_guid::little-64,
        drag_drop1::little-64,
        _item2_guid::little-64,
        drag_drop2::little-64
      >> = binary

      # Item1 moved to equipped slot
      # :equipped
      assert Bitwise.band(drag_drop1, 0xFF) == 0
      assert Bitwise.bsr(drag_drop1, 16) == 2

      # Item2 moved to bag slot
      # :bag
      assert Bitwise.band(drag_drop2, 0xFF) == 1
      assert Bitwise.bsr(drag_drop2, 16) == 0
    end
  end

  describe "new/2" do
    test "creates packet from item structs" do
      item1 = %{id: 1, container_type: :bag, bag_index: 0, slot: 1}
      item2 = %{id: 2, container_type: :equipped, bag_index: 0, slot: 3}

      packet = ServerItemSwap.new(item1, item2)

      assert packet.item1_guid == 1
      assert packet.item1_location == :bag
      assert packet.item2_guid == 2
      assert packet.item2_location == :equipped
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerItemSwap.opcode() == :server_item_swap
    end
  end
end
