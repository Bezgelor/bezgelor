defmodule BezgelorProtocol.PacketTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packet

  describe "header constants" do
    test "header size is 6 bytes" do
      assert Packet.header_size() == 6
    end
  end

  describe "parse_header/1" do
    test "parses valid header" do
      # Size = 10, Opcode = 3 (ServerHello)
      header = <<10, 0, 0, 0, 3, 0>>
      assert {:ok, 10, 0x0003} = Packet.parse_header(header)
    end

    test "returns error for incomplete header" do
      assert {:error, :incomplete} = Packet.parse_header(<<1, 2, 3>>)
    end
  end

  describe "build_header/2" do
    test "builds header from size and opcode" do
      header = Packet.build_header(10, 0x0003)
      assert header == <<10, 0, 0, 0, 3, 0>>
    end
  end

  describe "packet_size/1" do
    test "calculates total packet size from payload size" do
      # Size field = 4 + payload_size
      assert Packet.packet_size(0) == 4
      assert Packet.packet_size(100) == 104
    end
  end

  describe "payload_size/1" do
    test "calculates payload size from size field" do
      assert Packet.payload_size(4) == 0
      assert Packet.payload_size(104) == 100
    end
  end
end
