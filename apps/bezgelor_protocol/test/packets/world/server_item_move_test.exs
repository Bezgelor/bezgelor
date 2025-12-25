defmodule BezgelorProtocol.Packets.World.ServerItemMoveTest do
  @moduledoc """
  Tests for ServerItemMove packet serialization.

  Wire format uses NexusForever's ItemLocationToDragDropData encoding:
  drag_drop = (location << 8) | slot
  """
  use ExUnit.Case, async: true

  import Bitwise

  alias BezgelorProtocol.Packets.World.ServerItemMove
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "encodes item move to bag" do
      # new/3: item_guid, location, slot
      packet = ServerItemMove.new(12345, :bag, 5)
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemMove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Parse to verify encoding
      <<item_guid::little-64, drag_drop::little-64>> = binary

      assert item_guid == 12345

      # Decode drag_drop: (location << 8) | slot per NexusForever
      location = (drag_drop >>> 8) &&& 0xFF
      slot = drag_drop &&& 0xFF

      # :bag = 1
      assert location == 1
      assert slot == 5
    end

    test "encodes item move to equipped slot" do
      packet = ServerItemMove.new(99999, :equipped, 3)
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemMove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_item_guid::little-64, drag_drop::little-64>> = binary

      location = (drag_drop >>> 8) &&& 0xFF
      slot = drag_drop &&& 0xFF

      # :equipped = 0
      assert location == 0
      assert slot == 3
    end

    test "encodes item move to bank" do
      packet = ServerItemMove.new(77777, :bank, 10)
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemMove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_item_guid::little-64, drag_drop::little-64>> = binary

      location = (drag_drop >>> 8) &&& 0xFF
      slot = drag_drop &&& 0xFF

      # :bank = 2
      assert location == 2
      assert slot == 10
    end

    test "encodes item move to trade" do
      packet = ServerItemMove.new(55555, :trade, 0)
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemMove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_item_guid::little-64, drag_drop::little-64>> = binary

      location = (drag_drop >>> 8) &&& 0xFF
      slot = drag_drop &&& 0xFF

      # :trade = 3
      assert location == 3
      assert slot == 0
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerItemMove.opcode() == :server_item_move
    end
  end
end
