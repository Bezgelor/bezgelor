defmodule BezgelorProtocol.Packets.World.ServerChatNpcTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerChatNpc
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "serializes NPC chat packet" do
      packet = %ServerChatNpc{
        channel_type: 24,
        chat_id: 0,
        unit_name_text_id: 19245,
        message_text_id: 19246
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerChatNpc.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      # Verify the packet has data
      assert byte_size(data) > 0
    end

    test "channel type constant helper returns 24 for npc_say" do
      assert ServerChatNpc.npc_say() == 24
    end

    test "channel type constant helper returns 25 for npc_yell" do
      assert ServerChatNpc.npc_yell() == 25
    end

    test "channel type constant helper returns 26 for npc_whisper" do
      assert ServerChatNpc.npc_whisper() == 26
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerChatNpc.opcode() == :server_chat_npc
    end
  end
end
