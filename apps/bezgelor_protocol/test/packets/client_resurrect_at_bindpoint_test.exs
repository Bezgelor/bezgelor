defmodule BezgelorProtocol.Packets.World.ClientResurrectAtBindpointTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ClientResurrectAtBindpoint
  alias BezgelorProtocol.PacketReader

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ClientResurrectAtBindpoint.opcode() == :client_resurrect_at_bindpoint
    end
  end

  describe "read/1" do
    test "parses empty packet" do
      # Empty payload - packet has no data
      reader = PacketReader.new(<<>>)

      {:ok, packet, _reader} = ClientResurrectAtBindpoint.read(reader)

      assert %ClientResurrectAtBindpoint{} = packet
    end

    test "ignores trailing data" do
      # If there's any trailing data, it should still parse
      reader = PacketReader.new(<<0xFF, 0xFF>>)

      {:ok, packet, _reader} = ClientResurrectAtBindpoint.read(reader)

      assert %ClientResurrectAtBindpoint{} = packet
    end
  end
end
