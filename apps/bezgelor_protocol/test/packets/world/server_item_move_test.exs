defmodule BezgelorProtocol.Packets.World.ServerItemMoveTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerItemMove
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "encodes item move to bag" do
      packet = ServerItemMove.new(12345, :bag, 0, 5)
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemMove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Parse to verify encoding
      <<item_guid::little-64, drag_drop::little-64>> = binary

      assert item_guid == 12345

      # Decode drag_drop: location in bits 0-7, bag_index in 8-15, slot in 16+
      location = Bitwise.band(drag_drop, 0xFF)
      bag_index = Bitwise.band(Bitwise.bsr(drag_drop, 8), 0xFF)
      slot = Bitwise.bsr(drag_drop, 16)

      assert location == 1  # :bag
      assert bag_index == 0
      assert slot == 5
    end

    test "encodes item move to equipped slot" do
      packet = ServerItemMove.new(99999, :equipped, 0, 3)
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemMove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_item_guid::little-64, drag_drop::little-64>> = binary

      location = Bitwise.band(drag_drop, 0xFF)
      slot = Bitwise.bsr(drag_drop, 16)

      assert location == 0  # :equipped
      assert slot == 3
    end

    test "encodes item move to bank" do
      packet = ServerItemMove.new(77777, :bank, 2, 10)
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemMove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_item_guid::little-64, drag_drop::little-64>> = binary

      location = Bitwise.band(drag_drop, 0xFF)
      bag_index = Bitwise.band(Bitwise.bsr(drag_drop, 8), 0xFF)
      slot = Bitwise.bsr(drag_drop, 16)

      assert location == 2  # :bank
      assert bag_index == 2
      assert slot == 10
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerItemMove.opcode() == :server_item_move
    end
  end
end
