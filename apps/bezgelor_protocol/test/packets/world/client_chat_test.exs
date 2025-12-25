defmodule BezgelorProtocol.Packets.World.ClientChatTest do
  @moduledoc """
  Tests for ClientChat packet parsing.

  The wire format uses bit-packed wide strings:
  - 1 bit: extended flag (0 for short strings, 1 for long)
  - 7 or 15 bits: length in characters
  - length * 2 bytes: UTF-16LE string data
  """
  use ExUnit.Case, async: true

  import Bitwise

  alias BezgelorProtocol.Packets.World.ClientChat
  alias BezgelorProtocol.PacketReader

  describe "read/1" do
    test "reads say channel message" do
      # channel: uint32 (0 = say)
      # target: bit-packed wide string (empty)
      # message: bit-packed wide string "Hello"
      payload =
        <<0::32-little>> <>
          build_wide_string("") <>
          build_wide_string("Hello")

      reader = PacketReader.new(payload)
      assert {:ok, packet, _reader} = ClientChat.read(reader)

      assert %ClientChat{} = packet
      assert packet.channel == :say
      assert packet.target == nil
      assert packet.message == "Hello"
    end

    test "reads whisper with target" do
      # channel: uint32 (2 = whisper)
      # target: bit-packed wide string "Player"
      # message: bit-packed wide string "Hi"
      payload =
        <<2::32-little>> <>
          build_wide_string("Player") <>
          build_wide_string("Hi")

      reader = PacketReader.new(payload)
      assert {:ok, packet, _reader} = ClientChat.read(reader)

      assert packet.channel == :whisper
      assert packet.target == "Player"
      assert packet.message == "Hi"
    end

    test "reads yell channel" do
      payload =
        <<1::32-little>> <>
          build_wide_string("") <>
          build_wide_string("Hey!")

      reader = PacketReader.new(payload)
      assert {:ok, packet, _reader} = ClientChat.read(reader)

      assert packet.channel == :yell
      assert packet.target == nil
      assert packet.message == "Hey!"
    end

    test "reads emote channel" do
      payload =
        <<4::32-little>> <>
          build_wide_string("") <>
          build_wide_string("waves")

      reader = PacketReader.new(payload)
      assert {:ok, packet, _reader} = ClientChat.read(reader)

      assert packet.channel == :emote
      assert packet.message == "waves"
    end

    test "reads zone channel" do
      payload =
        <<7::32-little>> <>
          build_wide_string("") <>
          build_wide_string("Zone message")

      reader = PacketReader.new(payload)
      assert {:ok, packet, _reader} = ClientChat.read(reader)

      assert packet.channel == :zone
      assert packet.message == "Zone message"
    end
  end

  describe "opcode/0" do
    test "returns client_chat opcode" do
      assert :client_chat == ClientChat.opcode()
    end
  end

  describe "struct" do
    test "has expected fields" do
      packet = %ClientChat{channel: :say, target: nil, message: "test"}

      assert packet.channel == :say
      assert packet.target == nil
      assert packet.message == "test"
    end
  end

  # Build a bit-packed wide string matching NexusForever format:
  # - 1 bit: extended flag (0 for length < 128, 1 for length >= 128)
  # - 7 or 15 bits: length in characters
  # - length * 2 bytes: UTF-16LE string data
  #
  # Since read_bytes flushes bits first, each wide string is effectively
  # byte-aligned after the previous one's data.
  defp build_wide_string("") do
    # Empty string: extended=0, length=0, no data
    # Byte: 0b00000000 (bit 0 = extended, bits 1-7 = length)
    <<0::8>>
  end

  defp build_wide_string(string) when is_binary(string) do
    length = String.length(string)
    utf16_data = :unicode.characters_to_binary(string, :utf8, {:utf16, :little})

    if length < 128 do
      # Short string: extended=0 (bit 0), length in bits 1-7
      # Pack as: bit 0 = extended, bits 1-7 = length (LSB first)
      header = (length <<< 1) ||| 0
      <<header::8>> <> utf16_data
    else
      # Long string: extended=1 (bit 0), length in bits 1-15
      # Pack as: bit 0 = extended, bits 1-15 = length (LSB first)
      header = (length <<< 1) ||| 1
      <<header::16-little>> <> utf16_data
    end
  end
end
