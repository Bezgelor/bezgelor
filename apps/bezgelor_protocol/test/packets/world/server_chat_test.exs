defmodule BezgelorProtocol.Packets.World.ServerChatTest do
  @moduledoc """
  Tests for ServerChat packet serialization.

  Wire format uses bit-packed wide strings (not 32-bit length prefix).
  """
  use ExUnit.Case, async: true

  import Bitwise

  alias BezgelorProtocol.Packets.World.ServerChat
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "writes say channel message" do
      packet = %ServerChat{
        channel: :say,
        sender_guid: 0x1234567890ABCDEF,
        sender_name: "Test",
        message: "Hello"
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerChat.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Parse: channel (u32) + sender_guid (u64) + sender_name (wide_string) + message (wide_string)
      <<channel_int::32-little, guid::64-little, rest::binary>> = binary
      assert channel_int == 0
      assert guid == 0x1234567890ABCDEF

      # Parse bit-packed wide strings
      {sender_name, rest} = parse_wide_string(rest)
      {message, _rest} = parse_wide_string(rest)

      assert sender_name == "Test"
      assert message == "Hello"
    end

    test "writes whisper channel message" do
      packet = %ServerChat{
        channel: :whisper,
        sender_guid: 100,
        sender_name: "From Player",
        message: "Secret message"
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerChat.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<channel_int::32-little, _rest::binary>> = binary
      assert channel_int == 2
    end

    test "writes system message with zero guid" do
      packet = %ServerChat{
        channel: :system,
        sender_guid: 0,
        sender_name: "System",
        message: "Server restart in 5 minutes"
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerChat.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<channel_int::32-little, guid::64-little, rest::binary>> = binary
      assert channel_int == 3
      assert guid == 0

      {sender_name, rest} = parse_wide_string(rest)
      {message, _rest} = parse_wide_string(rest)

      assert sender_name == "System"
      assert message == "Server restart in 5 minutes"
    end
  end

  describe "helper constructors" do
    test "say/3 creates say channel packet" do
      packet = ServerChat.say(123, "Player", "Hello world")

      assert %ServerChat{} = packet
      assert packet.channel == :say
      assert packet.sender_guid == 123
      assert packet.sender_name == "Player"
      assert packet.message == "Hello world"
    end

    test "yell/3 creates yell channel packet" do
      packet = ServerChat.yell(456, "Shouter", "LOUD!")

      assert packet.channel == :yell
      assert packet.sender_guid == 456
      assert packet.sender_name == "Shouter"
      assert packet.message == "LOUD!"
    end

    test "whisper/3 creates whisper channel packet" do
      packet = ServerChat.whisper(789, "Whisperer", "Shh...")

      assert packet.channel == :whisper
      assert packet.message == "Shh..."
    end

    test "emote/3 creates emote channel packet" do
      packet = ServerChat.emote(111, "Emoter", "waves")

      assert packet.channel == :emote
      assert packet.message == "waves"
    end

    test "system/1 creates system message with zero guid" do
      packet = ServerChat.system("Server announcement")

      assert packet.channel == :system
      assert packet.sender_guid == 0
      assert packet.sender_name == "System"
      assert packet.message == "Server announcement"
    end
  end

  describe "opcode/0" do
    test "returns server_chat opcode" do
      assert :server_chat == ServerChat.opcode()
    end
  end

  # Helper to parse bit-packed wide string
  defp parse_wide_string(<<header::8, rest::binary>>) do
    extended = (header &&& 1) == 1

    if extended do
      <<second_byte::8, data::binary>> = rest
      length = ((second_byte <<< 7) ||| (header >>> 1)) &&& 0x7FFF
      byte_length = length * 2
      <<utf16::binary-size(byte_length), remaining::binary>> = data
      string = :unicode.characters_to_binary(utf16, {:utf16, :little}, :utf8)
      {string, remaining}
    else
      length = header >>> 1
      byte_length = length * 2
      <<utf16::binary-size(byte_length), remaining::binary>> = rest
      string = :unicode.characters_to_binary(utf16, {:utf16, :little}, :utf8)
      {string, remaining}
    end
  end
end
