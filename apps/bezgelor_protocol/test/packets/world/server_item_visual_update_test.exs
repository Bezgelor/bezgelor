defmodule BezgelorProtocol.Packets.World.ServerItemVisualUpdateTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerItemVisualUpdate
  alias BezgelorProtocol.PacketWriter

  import Bitwise

  describe "write/2" do
    test "encodes empty visuals list" do
      packet = ServerItemVisualUpdate.new(12345, [])
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemVisualUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # 4 bytes player_guid + 1 byte count
      assert byte_size(binary) == 5

      <<player_guid::little-32, count::8>> = binary
      assert player_guid == 12345
      assert count == 0
    end

    test "encodes single visual" do
      visual = ServerItemVisualUpdate.visual(3, 1000, 5, 0)
      packet = ServerItemVisualUpdate.new(99999, [visual])
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemVisualUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # 4 bytes player_guid + 1 byte count + bit-packed visual + 4 bytes dye_data
      # Bit-packed: 7 + 15 + 14 = 36 bits = 5 bytes (padded)
      # Total: 4 + 1 + 5 + 4 = 14 bytes
      assert byte_size(binary) == 14

      <<player_guid::little-32, count::8, rest::binary>> = binary
      assert player_guid == 99999
      assert count == 1

      # Parse bit-packed visual
      <<bits::binary-size(5), dye_data::little-signed-32>> = rest

      # Extract bits manually (little-endian bit order)
      <<b0, b1, b2, b3, b4>> = bits

      # slot is in first 7 bits
      slot = Bitwise.band(b0, 0x7F)
      assert slot == 3

      # display_id is next 15 bits (bits 7-21)
      # 1 bit from b0
      display_id_low = Bitwise.bsr(b0, 7)
      # 8 bits from b1
      display_id_mid = b1
      # 6 bits from b2
      display_id_high = Bitwise.band(b2, 0x3F)
      display_id = display_id_low ||| display_id_mid <<< 1 ||| display_id_high <<< 9
      assert display_id == 1000

      # colour_set is next 14 bits (bits 22-35)
      # 2 bits from b2
      colour_set_low = Bitwise.bsr(b2, 6)
      # 8 bits from b3
      colour_set_mid = b3
      # 4 bits from b4
      colour_set_high = Bitwise.band(b4, 0x0F)
      colour_set = colour_set_low ||| colour_set_mid <<< 2 ||| colour_set_high <<< 10
      assert colour_set == 5

      assert dye_data == 0
    end

    test "encodes multiple visuals" do
      visuals = [
        ServerItemVisualUpdate.visual(0, 100, 0, 0),
        ServerItemVisualUpdate.visual(1, 200, 1, -1),
        ServerItemVisualUpdate.visual(2, 300, 2, 100)
      ]

      packet = ServerItemVisualUpdate.new(55555, visuals)
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemVisualUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_player_guid::little-32, count::8, _rest::binary>> = binary
      assert count == 3
    end

    test "handles negative dye_data" do
      visual = ServerItemVisualUpdate.visual(5, 500, 10, -12345)
      packet = ServerItemVisualUpdate.new(11111, [visual])
      writer = PacketWriter.new()

      assert {:ok, writer} = ServerItemVisualUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Extract dye_data (last 4 bytes)
      binary_size = byte_size(binary)
      dye_offset = binary_size - 4
      <<_header::binary-size(dye_offset), dye_data::little-signed-32>> = binary

      assert dye_data == -12345
    end
  end

  describe "visual/4" do
    test "creates visual map with defaults" do
      visual = ServerItemVisualUpdate.visual(3, 1000)
      assert visual.slot == 3
      assert visual.display_id == 1000
      assert visual.colour_set == 0
      assert visual.dye_data == 0
    end

    test "creates visual map with all fields" do
      visual = ServerItemVisualUpdate.visual(5, 2000, 15, -100)
      assert visual.slot == 5
      assert visual.display_id == 2000
      assert visual.colour_set == 15
      assert visual.dye_data == -100
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerItemVisualUpdate.opcode() == :server_item_visual_update
    end
  end
end
