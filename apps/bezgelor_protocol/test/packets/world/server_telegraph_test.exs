defmodule BezgelorProtocol.Packets.World.ServerTelegraphTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerTelegraph
  alias BezgelorProtocol.PacketWriter

  describe "circle/5" do
    test "creates circle telegraph packet" do
      packet = ServerTelegraph.circle(12345, {10.0, 20.0, 30.0}, 8.0, 2000, :red)

      assert packet.caster_guid == 12345
      assert packet.shape == :circle
      assert packet.position == {10.0, 20.0, 30.0}
      assert packet.params.radius == 8.0
      assert packet.duration == 2000
      assert packet.color == :red
    end
  end

  describe "cone/7" do
    test "creates cone telegraph packet" do
      packet = ServerTelegraph.cone(12345, {0.0, 0.0, 0.0}, 90.0, 15.0, 1.57, 2000, :red)

      assert packet.caster_guid == 12345
      assert packet.shape == :cone
      assert packet.position == {0.0, 0.0, 0.0}
      assert packet.params.angle == 90.0
      assert packet.params.length == 15.0
      assert packet.rotation == 1.57
      assert packet.duration == 2000
      assert packet.color == :red
    end
  end

  describe "rectangle/7" do
    test "creates rectangle telegraph packet" do
      packet = ServerTelegraph.rectangle(12345, {5.0, 10.0, 15.0}, 4.0, 10.0, 0.0, 1500, :yellow)

      assert packet.caster_guid == 12345
      assert packet.shape == :rectangle
      assert packet.position == {5.0, 10.0, 15.0}
      assert packet.params.width == 4.0
      assert packet.params.length == 10.0
      assert packet.rotation == 0.0
      assert packet.duration == 1500
      assert packet.color == :yellow
    end
  end

  describe "donut/6" do
    test "creates donut telegraph packet" do
      packet = ServerTelegraph.donut(12345, {0.0, 0.0, 0.0}, 5.0, 15.0, 3000, :green)

      assert packet.caster_guid == 12345
      assert packet.shape == :donut
      assert packet.position == {0.0, 0.0, 0.0}
      assert packet.params.inner_radius == 5.0
      assert packet.params.outer_radius == 15.0
      assert packet.duration == 3000
      assert packet.color == :green
    end
  end

  describe "write/2" do
    test "writes circle telegraph" do
      packet = ServerTelegraph.circle(12345, {10.0, 20.0, 30.0}, 8.0, 2000, :red)

      writer = PacketWriter.new()
      {:ok, writer} = ServerTelegraph.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      # Should serialize without error
      assert byte_size(data) > 0

      # Verify structure:
      # uint64 caster_guid (8) + uint32 spell_id (4) + uint8 shape (1) +
      # 3x float32 position (12) + float32 rotation (4) +
      # uint32 duration (4) + uint8 color (1) + float32 radius (4)
      # Total: 8 + 4 + 1 + 12 + 4 + 4 + 1 + 4 = 38 bytes
      assert byte_size(data) == 38
    end

    test "writes cone telegraph" do
      packet = ServerTelegraph.cone(12345, {0.0, 0.0, 0.0}, 90.0, 15.0, 0.0, 2000, :red)

      writer = PacketWriter.new()
      {:ok, writer} = ServerTelegraph.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      # Cone has 2 float params (angle, length) = 8 extra bytes
      # 38 base - 4 (circle radius) + 8 (cone params) = 42 bytes
      assert byte_size(data) == 42
    end

    test "writes rectangle telegraph" do
      packet = ServerTelegraph.rectangle(12345, {0.0, 0.0, 0.0}, 4.0, 10.0, 0.0, 2000, :yellow)

      writer = PacketWriter.new()
      {:ok, writer} = ServerTelegraph.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      # Rectangle has 2 float params (width, length) = 8 extra bytes
      assert byte_size(data) == 42
    end

    test "writes donut telegraph" do
      packet = ServerTelegraph.donut(12345, {0.0, 0.0, 0.0}, 5.0, 15.0, 3000, :green)

      writer = PacketWriter.new()
      {:ok, writer} = ServerTelegraph.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      # Donut has 2 float params (inner_radius, outer_radius) = 8 extra bytes
      assert byte_size(data) == 42
    end

    test "opcode returns correct value" do
      assert ServerTelegraph.opcode() == :server_telegraph
    end
  end

  describe "colors" do
    test "all color values are valid" do
      for color <- [:red, :blue, :yellow, :green] do
        packet = ServerTelegraph.circle(1, {0.0, 0.0, 0.0}, 1.0, 1000, color)

        writer = PacketWriter.new()
        {:ok, _writer} = ServerTelegraph.write(packet, writer)
      end
    end
  end
end
