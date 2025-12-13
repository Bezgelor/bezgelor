defmodule BezgelorProtocol.Packets.QuestPacketsTest do
  @moduledoc """
  Tests for quest-related packet serialization and deserialization.

  Validates wire format compliance and round-trip encoding.
  """
  use ExUnit.Case, async: true

  alias BezgelorProtocol.PacketWriter
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.{
    ServerQuestAdd,
    ServerQuestUpdate,
    ServerQuestRemove,
    ClientAcceptQuest,
    ClientAbandonQuest,
    ClientTurnInQuest
  }

  # ============================================================================
  # ServerQuestAdd Tests
  # ============================================================================

  describe "ServerQuestAdd" do
    test "writes quest with single objective" do
      packet = %ServerQuestAdd{
        quest_id: 12345,
        objectives: [%{target: 5}]
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestAdd.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Expected format:
      # quest_id: uint32 (4 bytes) = 12345
      # objective_count: uint8 (1 byte) = 1
      # objective[0].target: uint16 (2 bytes) = 5
      assert byte_size(binary) == 7

      <<quest_id::little-32, count::8, target::little-16>> = binary
      assert quest_id == 12345
      assert count == 1
      assert target == 5
    end

    test "writes quest with multiple objectives" do
      packet = %ServerQuestAdd{
        quest_id: 5861,
        objectives: [
          %{target: 3},
          %{target: 10},
          %{target: 1}
        ]
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestAdd.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # quest_id(4) + count(1) + 3 objectives * target(2) = 11 bytes
      assert byte_size(binary) == 11

      <<quest_id::little-32, count::8, t1::little-16, t2::little-16, t3::little-16>> = binary
      assert quest_id == 5861
      assert count == 3
      assert t1 == 3
      assert t2 == 10
      assert t3 == 1
    end

    test "writes quest with no objectives" do
      packet = %ServerQuestAdd{
        quest_id: 100,
        objectives: []
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestAdd.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      assert byte_size(binary) == 5
      <<quest_id::little-32, count::8>> = binary
      assert quest_id == 100
      assert count == 0
    end

    test "handles string key objectives" do
      packet = %ServerQuestAdd{
        quest_id: 200,
        objectives: [%{"target" => 15}]
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestAdd.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_quest_id::little-32, _count::8, target::little-16>> = binary
      assert target == 15
    end

    test "returns correct opcode" do
      assert ServerQuestAdd.opcode() == :server_quest_add
    end
  end

  # ============================================================================
  # ServerQuestUpdate Tests
  # ============================================================================

  describe "ServerQuestUpdate" do
    test "writes progress update" do
      packet = %ServerQuestUpdate{
        quest_id: 5861,
        state: :accepted,
        objective_index: 0,
        current: 5
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # quest_id(4) + state(1) + index(1) + current(2) = 8 bytes
      assert byte_size(binary) == 8

      <<quest_id::little-32, state::8, index::8, current::little-16>> = binary
      assert quest_id == 5861
      assert state == 0  # :accepted = 0
      assert index == 0
      assert current == 5
    end

    test "encodes :complete state correctly" do
      packet = %ServerQuestUpdate{
        quest_id: 100,
        state: :complete,
        objective_index: 2,
        current: 10
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_quest_id::little-32, state::8, index::8, current::little-16>> = binary
      assert state == 1  # :complete = 1
      assert index == 2
      assert current == 10
    end

    test "encodes :failed state correctly" do
      packet = %ServerQuestUpdate{
        quest_id: 100,
        state: :failed,
        objective_index: 0,
        current: 0
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_::little-32, state::8, _::binary>> = binary
      assert state == 2  # :failed = 2
    end

    test "handles unknown state gracefully" do
      packet = %ServerQuestUpdate{
        quest_id: 100,
        state: :unknown_state,
        objective_index: 0,
        current: 0
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_::little-32, state::8, _::binary>> = binary
      assert state == 0  # defaults to 0
    end

    test "returns correct opcode" do
      assert ServerQuestUpdate.opcode() == :server_quest_update
    end
  end

  # ============================================================================
  # ServerQuestRemove Tests
  # ============================================================================

  describe "ServerQuestRemove" do
    test "writes abandoned quest removal" do
      packet = %ServerQuestRemove{
        quest_id: 5861,
        reason: :abandoned
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestRemove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # quest_id(4) + reason(1) = 5 bytes
      assert byte_size(binary) == 5

      <<quest_id::little-32, reason::8>> = binary
      assert quest_id == 5861
      assert reason == 0  # :abandoned = 0
    end

    test "writes completed quest removal" do
      packet = %ServerQuestRemove{
        quest_id: 100,
        reason: :completed
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestRemove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_::little-32, reason::8>> = binary
      assert reason == 1  # :completed = 1
    end

    test "writes failed quest removal" do
      packet = %ServerQuestRemove{
        quest_id: 200,
        reason: :failed
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestRemove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_::little-32, reason::8>> = binary
      assert reason == 2  # :failed = 2
    end

    test "handles nil reason" do
      packet = %ServerQuestRemove{
        quest_id: 300,
        reason: nil
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestRemove.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_::little-32, reason::8>> = binary
      assert reason == 0  # defaults to 0
    end

    test "returns correct opcode" do
      assert ServerQuestRemove.opcode() == :server_quest_remove
    end
  end

  # ============================================================================
  # ClientAcceptQuest Tests
  # ============================================================================

  describe "ClientAcceptQuest" do
    test "reads accept quest packet" do
      # Build binary: quest_id(4) + npc_guid(8) = 12 bytes
      quest_id = 5861
      npc_guid = 0x0001000000000001

      binary = <<quest_id::little-32, npc_guid::little-64>>
      reader = PacketReader.new(binary)

      {:ok, packet, _reader} = ClientAcceptQuest.read(reader)

      assert packet.quest_id == 5861
      assert packet.npc_guid == npc_guid
    end

    test "reads quest with zero npc_guid" do
      binary = <<100::little-32, 0::little-64>>
      reader = PacketReader.new(binary)

      {:ok, packet, _reader} = ClientAcceptQuest.read(reader)

      assert packet.quest_id == 100
      assert packet.npc_guid == 0
    end

    test "returns correct opcode" do
      assert ClientAcceptQuest.opcode() == :client_accept_quest
    end
  end

  # ============================================================================
  # ClientAbandonQuest Tests
  # ============================================================================

  describe "ClientAbandonQuest" do
    test "reads abandon quest packet" do
      binary = <<5861::little-32>>
      reader = PacketReader.new(binary)

      {:ok, packet, _reader} = ClientAbandonQuest.read(reader)

      assert packet.quest_id == 5861
    end

    test "returns correct opcode" do
      assert ClientAbandonQuest.opcode() == :client_abandon_quest
    end
  end

  # ============================================================================
  # ClientTurnInQuest Tests
  # ============================================================================

  describe "ClientTurnInQuest" do
    test "reads turn in quest packet" do
      quest_id = 5861
      npc_guid = 0x0001000000000002
      reward_choice = 0

      # quest_id(4) + npc_guid(8) + reward_choice(1) = 13 bytes
      binary = <<quest_id::little-32, npc_guid::little-64, reward_choice::8>>
      reader = PacketReader.new(binary)

      {:ok, packet, _reader} = ClientTurnInQuest.read(reader)

      assert packet.quest_id == 5861
      assert packet.npc_guid == npc_guid
      assert packet.reward_choice == 0
    end

    test "reads turn in with reward choice" do
      quest_id = 100
      npc_guid = 0x0001000000000003
      reward_choice = 2  # Second reward option

      binary = <<quest_id::little-32, npc_guid::little-64, reward_choice::8>>
      reader = PacketReader.new(binary)

      {:ok, packet, _reader} = ClientTurnInQuest.read(reader)

      assert packet.quest_id == 100
      assert packet.reward_choice == 2
    end

    test "returns correct opcode" do
      assert ClientTurnInQuest.opcode() == :client_turn_in_quest
    end
  end

  # ============================================================================
  # Wire Format Validation Tests
  # ============================================================================

  describe "wire format validation" do
    test "ServerQuestAdd maintains little-endian byte order" do
      packet = %ServerQuestAdd{
        quest_id: 0x12345678,
        objectives: [%{target: 0xABCD}]
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestAdd.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Verify little-endian: least significant byte first
      <<b0, b1, b2, b3, _count, t0, t1>> = binary

      # quest_id 0x12345678 in little-endian: 78 56 34 12
      assert b0 == 0x78
      assert b1 == 0x56
      assert b2 == 0x34
      assert b3 == 0x12

      # target 0xABCD in little-endian: CD AB
      assert t0 == 0xCD
      assert t1 == 0xAB
    end

    test "ServerQuestUpdate uses correct field sizes" do
      packet = %ServerQuestUpdate{
        quest_id: 0xFFFFFFFF,  # max uint32
        state: :accepted,
        objective_index: 255,  # max uint8
        current: 0xFFFF  # max uint16
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerQuestUpdate.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # Must be exactly 8 bytes
      assert byte_size(binary) == 8

      <<quest_id::little-32, _state::8, index::8, current::little-16>> = binary
      assert quest_id == 0xFFFFFFFF
      assert index == 255
      assert current == 0xFFFF
    end
  end
end
