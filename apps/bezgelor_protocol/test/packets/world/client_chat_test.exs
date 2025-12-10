defmodule BezgelorProtocol.Packets.World.ClientChatTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ClientChat
  alias BezgelorProtocol.PacketReader

  describe "read/1" do
    test "reads say channel message" do
      # channel: uint32 (0 = say)
      # target: wide string (empty)
      # message: wide string "Hello"
      payload =
        <<0::32-little>> <>
          <<0::32-little>> <>
          <<5::32-little, "H"::utf8, 0, "e"::utf8, 0, "l"::utf8, 0, "l"::utf8, 0, "o"::utf8, 0>>

      reader = PacketReader.new(payload)
      assert {:ok, packet, _reader} = ClientChat.read(reader)

      assert %ClientChat{} = packet
      assert packet.channel == :say
      # Empty target is converted to nil
      assert packet.target == nil
      assert packet.message == "Hello"
    end

    test "reads whisper with target" do
      # channel: uint32 (2 = whisper)
      # target: wide string "Player"
      # message: wide string "Hi"
      target_str = <<6::32-little, "P"::utf8, 0, "l"::utf8, 0, "a"::utf8, 0, "y"::utf8, 0, "e"::utf8, 0, "r"::utf8, 0>>
      message_str = <<2::32-little, "H"::utf8, 0, "i"::utf8, 0>>

      payload = <<2::32-little>> <> target_str <> message_str

      reader = PacketReader.new(payload)
      assert {:ok, packet, _reader} = ClientChat.read(reader)

      assert packet.channel == :whisper
      assert packet.target == "Player"
      assert packet.message == "Hi"
    end

    test "reads yell channel" do
      payload =
        <<1::32-little>> <>
          <<0::32-little>> <>
          <<4::32-little, "H"::utf8, 0, "e"::utf8, 0, "y"::utf8, 0, "!"::utf8, 0>>

      reader = PacketReader.new(payload)
      assert {:ok, packet, _reader} = ClientChat.read(reader)

      assert packet.channel == :yell
      assert packet.message == "Hey!"
    end

    test "reads emote channel" do
      payload =
        <<4::32-little>> <>
          <<0::32-little>> <>
          <<5::32-little, "w"::utf8, 0, "a"::utf8, 0, "v"::utf8, 0, "e"::utf8, 0, "s"::utf8, 0>>

      reader = PacketReader.new(payload)
      assert {:ok, packet, _reader} = ClientChat.read(reader)

      assert packet.channel == :emote
      assert packet.message == "waves"
    end
  end

  describe "opcode/0" do
    test "returns client_chat opcode" do
      assert :client_chat == ClientChat.opcode()
    end
  end
end
