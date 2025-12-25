defmodule BezgelorProtocol.PacketTest do
  @moduledoc """
  Tests for packet header utilities.

  Wire format: Size (4 bytes) + Opcode (2 bytes) + Payload (variable)
  Size field = 6 (header) + payload_length
  """
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packet

  describe "header constants" do
    test "header size is 6 bytes" do
      assert Packet.header_size() == 6
    end
  end

  describe "parse_header/1" do
    test "parses valid header" do
      # Size = 10 (6 header + 4 payload), Opcode = 3 (ServerHello)
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
      # Size field = 6 (header: 4 size + 2 opcode) + payload_size
      assert Packet.packet_size(0) == 6
      assert Packet.packet_size(4) == 10
      assert Packet.packet_size(100) == 106
    end
  end

  describe "payload_size/1" do
    test "calculates payload size from size field" do
      # Payload = size - 6 (header)
      assert Packet.payload_size(6) == 0
      assert Packet.payload_size(10) == 4
      assert Packet.payload_size(106) == 100
    end
  end
end
