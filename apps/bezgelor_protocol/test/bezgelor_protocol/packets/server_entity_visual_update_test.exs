defmodule BezgelorProtocol.Packets.World.ServerEntityVisualUpdateTest do
  @moduledoc """
  Tests for ServerEntityVisualUpdate packet.
  """
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerEntityVisualUpdate
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "writes packet with no visuals" do
      packet = %ServerEntityVisualUpdate{
        unit_id: 12345,
        race: 1,
        sex: 0,
        creature_id: 0,
        display_info: 0,
        outfit_info: 0,
        item_color_set_id: 0,
        visuals: []
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerEntityVisualUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Should have written header fields (unit_id:32 + race:5 + sex:2 + creature_id:18 +
      # display_info:17 + outfit_info:15 + item_color_set_id:32 + unknown6:1 + count:32 = 154 bits)
      # 154 bits = 20 bytes with 6 bits padding
      assert byte_size(binary) >= 19
    end

    test "writes packet with visuals" do
      visuals = [
        %{slot: 1, display_id: 100, colour_set: 0, dye_data: 0},
        %{slot: 2, display_id: 200, colour_set: 0, dye_data: 0}
      ]

      packet = %ServerEntityVisualUpdate{
        unit_id: 12345,
        race: 1,
        sex: 0,
        creature_id: 0,
        display_info: 0,
        outfit_info: 0,
        item_color_set_id: 0,
        visuals: visuals
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerEntityVisualUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Each visual adds: slot:7 + display_id:15 + colour_set:14 + dye_data:32 = 68 bits
      # 2 visuals = 136 bits = 17 bytes
      # Header = ~20 bytes, so total should be ~37 bytes or more
      assert byte_size(binary) >= 35
    end

    test "struct has correct defaults" do
      packet = %ServerEntityVisualUpdate{}

      assert packet.unit_id == 0
      assert packet.race == 0
      assert packet.sex == 0
      assert packet.visuals == []
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerEntityVisualUpdate.opcode() == :server_entity_visual_update
    end
  end
end
