defmodule BezgelorProtocol.Packets.World.ServerChatResultTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerChatResult
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "writes success result" do
      packet = %ServerChatResult{result: :success, channel: :say}

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerChatResult.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<result_code::32-little, channel_int::32-little>> = binary
      assert result_code == 0
      assert channel_int == 0
    end

    test "writes player_not_found result" do
      packet = %ServerChatResult{result: :player_not_found, channel: :whisper}

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerChatResult.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<result_code::32-little, channel_int::32-little>> = binary
      assert result_code == 1
      assert channel_int == 2
    end

    test "writes muted result" do
      packet = %ServerChatResult{result: :muted, channel: :say}

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerChatResult.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<result_code::32-little, _channel_int::32-little>> = binary
      assert result_code == 3
    end

    test "writes channel_unavailable result" do
      packet = %ServerChatResult{result: :channel_unavailable, channel: :party}

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerChatResult.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<result_code::32-little, channel_int::32-little>> = binary
      assert result_code == 4
      assert channel_int == 5
    end

    test "writes message_too_long result" do
      packet = %ServerChatResult{result: :message_too_long, channel: :zone}

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerChatResult.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<result_code::32-little, _::32-little>> = binary
      assert result_code == 5
    end

    test "writes rate_limited result" do
      packet = %ServerChatResult{result: :rate_limited, channel: :say}

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerChatResult.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<result_code::32-little, _::32-little>> = binary
      assert result_code == 6
    end
  end

  describe "result_to_code/1" do
    test "converts result atoms to codes" do
      assert 0 == ServerChatResult.result_to_code(:success)
      assert 1 == ServerChatResult.result_to_code(:player_not_found)
      assert 2 == ServerChatResult.result_to_code(:player_offline)
      assert 3 == ServerChatResult.result_to_code(:muted)
      assert 4 == ServerChatResult.result_to_code(:channel_unavailable)
      assert 5 == ServerChatResult.result_to_code(:message_too_long)
      assert 6 == ServerChatResult.result_to_code(:rate_limited)
    end

    test "unknown results default to success" do
      assert 0 == ServerChatResult.result_to_code(:unknown)
    end
  end

  describe "code_to_result/1" do
    test "converts codes to result atoms" do
      assert :success == ServerChatResult.code_to_result(0)
      assert :player_not_found == ServerChatResult.code_to_result(1)
      assert :player_offline == ServerChatResult.code_to_result(2)
      assert :muted == ServerChatResult.code_to_result(3)
      assert :channel_unavailable == ServerChatResult.code_to_result(4)
      assert :message_too_long == ServerChatResult.code_to_result(5)
      assert :rate_limited == ServerChatResult.code_to_result(6)
    end

    test "unknown codes default to success" do
      assert :success == ServerChatResult.code_to_result(99)
    end
  end

  describe "helper constructors" do
    test "success/1 creates success result" do
      packet = ServerChatResult.success(:say)

      assert %ServerChatResult{} = packet
      assert packet.result == :success
      assert packet.channel == :say
    end

    test "player_not_found/0 creates whisper not found result" do
      packet = ServerChatResult.player_not_found()

      assert packet.result == :player_not_found
      assert packet.channel == :whisper
    end

    test "channel_unavailable/1 creates unavailable result" do
      packet = ServerChatResult.channel_unavailable(:party)

      assert packet.result == :channel_unavailable
      assert packet.channel == :party
    end
  end

  describe "opcode/0" do
    test "returns server_chat_result opcode" do
      assert :server_chat_result == ServerChatResult.opcode()
    end
  end
end
