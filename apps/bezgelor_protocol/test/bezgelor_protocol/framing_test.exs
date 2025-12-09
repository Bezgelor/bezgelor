defmodule BezgelorProtocol.FramingTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Framing

  describe "frame_packet/2" do
    test "frames payload with header" do
      payload = <<1, 2, 3, 4>>
      opcode = 0x0003

      framed = Framing.frame_packet(opcode, payload)

      # Size = 4 (size field) + 4 (payload) = 8
      # Header = 8 (size) + 3 (opcode) = 6 bytes
      assert framed == <<8, 0, 0, 0, 3, 0, 1, 2, 3, 4>>
    end
  end

  describe "parse_packets/1" do
    test "parses single complete packet" do
      data = <<8, 0, 0, 0, 3, 0, 1, 2, 3, 4>>

      assert {:ok, [{0x0003, <<1, 2, 3, 4>>}], <<>>} = Framing.parse_packets(data)
    end

    test "parses multiple packets" do
      packet1 = <<6, 0, 0, 0, 3, 0, 1, 2>>
      packet2 = <<5, 0, 0, 0, 4, 0, 0xFF>>
      data = packet1 <> packet2

      assert {:ok, packets, <<>>} = Framing.parse_packets(data)
      assert length(packets) == 2
      assert {0x0003, <<1, 2>>} in packets
      assert {0x0004, <<0xFF>>} in packets
    end

    test "returns remaining data for incomplete packet" do
      # Complete packet + incomplete
      complete = <<6, 0, 0, 0, 3, 0, 1, 2>>
      incomplete = <<10, 0, 0, 0, 4, 0>>  # Says 10 bytes but only 6 present

      data = complete <> incomplete

      assert {:ok, [{0x0003, <<1, 2>>}], ^incomplete} = Framing.parse_packets(data)
    end

    test "returns all data when header incomplete" do
      data = <<6, 0, 0>>  # Only 3 bytes, need 6 for header

      assert {:ok, [], ^data} = Framing.parse_packets(data)
    end
  end
end
