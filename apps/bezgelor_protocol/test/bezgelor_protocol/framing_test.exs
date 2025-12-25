defmodule BezgelorProtocol.FramingTest do
  @moduledoc """
  Tests for packet framing.

  Wire format: Size (4 bytes) + Opcode (2 bytes) + Payload (variable)
  Size field = 6 (header) + payload_length
  """
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Framing

  describe "frame_packet/2" do
    test "frames payload with header" do
      payload = <<1, 2, 3, 4>>
      opcode = 0x0003

      framed = Framing.frame_packet(opcode, payload)

      # Size = 6 (header: 4 size + 2 opcode) + 4 (payload) = 10
      # Wire format: size(4) + opcode(2) + payload(4) = 10 bytes total
      assert framed == <<10, 0, 0, 0, 3, 0, 1, 2, 3, 4>>
    end

    test "frames empty payload" do
      framed = Framing.frame_packet(0x0001, <<>>)

      # Size = 6 (header only, no payload)
      assert framed == <<6, 0, 0, 0, 1, 0>>
    end
  end

  describe "parse_packets/1" do
    test "parses single complete packet" do
      # 4-byte payload, size = 6 + 4 = 10
      data = <<10, 0, 0, 0, 3, 0, 1, 2, 3, 4>>

      assert {:ok, [{0x0003, <<1, 2, 3, 4>>}], <<>>} = Framing.parse_packets(data)
    end

    test "parses multiple packets" do
      # Packet 1: 2-byte payload, size = 6 + 2 = 8
      packet1 = <<8, 0, 0, 0, 3, 0, 1, 2>>
      # Packet 2: 1-byte payload, size = 6 + 1 = 7
      packet2 = <<7, 0, 0, 0, 4, 0, 0xFF>>
      data = packet1 <> packet2

      assert {:ok, packets, <<>>} = Framing.parse_packets(data)
      assert length(packets) == 2
      assert {0x0003, <<1, 2>>} in packets
      assert {0x0004, <<0xFF>>} in packets
    end

    test "returns remaining data for incomplete packet" do
      # Complete packet: 2-byte payload, size = 8
      complete = <<8, 0, 0, 0, 3, 0, 1, 2>>
      # Incomplete: says size=12 (6-byte payload) but only header present
      incomplete = <<12, 0, 0, 0, 4, 0>>

      data = complete <> incomplete

      assert {:ok, [{0x0003, <<1, 2>>}], ^incomplete} = Framing.parse_packets(data)
    end

    test "returns all data when header incomplete" do
      # Only 3 bytes, need 6 for header
      data = <<6, 0, 0>>

      assert {:ok, [], ^data} = Framing.parse_packets(data)
    end

    test "parses packet with no payload" do
      # Size = 6 (header only)
      data = <<6, 0, 0, 0, 5, 0>>

      assert {:ok, [{0x0005, <<>>}], <<>>} = Framing.parse_packets(data)
    end
  end
end
