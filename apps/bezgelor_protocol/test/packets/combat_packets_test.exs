defmodule BezgelorProtocol.Packets.CombatPacketsTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  alias BezgelorProtocol.Packets.World.{
    ClientSetTarget,
    ServerTargetUpdate,
    ServerEntityDeath,
    ClientRespawn,
    ServerRespawn,
    ServerXPGain,
    ServerLevelUp,
    ServerLootDrop
  }

  describe "ClientSetTarget" do
    test "reads target GUID" do
      # Build packet: uint64 target_guid
      data = <<12345::64-little>>
      reader = PacketReader.new(data)

      {:ok, packet, _} = ClientSetTarget.read(reader)

      assert packet.target_guid == 12345
    end

    test "reads zero for cleared target" do
      data = <<0::64-little>>
      reader = PacketReader.new(data)

      {:ok, packet, _} = ClientSetTarget.read(reader)

      assert packet.target_guid == 0
    end

    test "has correct opcode" do
      assert ClientSetTarget.opcode() == :client_set_target
    end
  end

  describe "ServerTargetUpdate" do
    test "writes entity and target GUIDs" do
      packet = %ServerTargetUpdate{
        entity_guid: 100,
        target_guid: 200
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerTargetUpdate.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      assert <<100::64-little, 200::64-little>> = data
    end

    test "writes 0 for nil target" do
      packet = %ServerTargetUpdate{
        entity_guid: 100,
        target_guid: nil
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerTargetUpdate.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      assert <<100::64-little, 0::64-little>> = data
    end

    test "has correct opcode" do
      assert ServerTargetUpdate.opcode() == :server_target_update
    end
  end

  describe "ServerEntityDeath" do
    test "writes entity and killer GUIDs" do
      packet = %ServerEntityDeath{
        entity_guid: 100,
        killer_guid: 200
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerEntityDeath.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      assert <<100::64-little, 200::64-little>> = data
    end

    test "writes 0 for nil killer" do
      packet = %ServerEntityDeath{
        entity_guid: 100,
        killer_guid: nil
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerEntityDeath.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      assert <<100::64-little, 0::64-little>> = data
    end

    test "has correct opcode" do
      assert ServerEntityDeath.opcode() == :server_entity_death
    end
  end

  describe "ClientRespawn" do
    test "reads same_location type" do
      data = <<0::32-little>>
      reader = PacketReader.new(data)

      {:ok, packet, _} = ClientRespawn.read(reader)

      assert packet.respawn_type == :same_location
    end

    test "reads graveyard type" do
      data = <<1::32-little>>
      reader = PacketReader.new(data)

      {:ok, packet, _} = ClientRespawn.read(reader)

      assert packet.respawn_type == :graveyard
    end

    test "defaults unknown type to same_location" do
      data = <<99::32-little>>
      reader = PacketReader.new(data)

      {:ok, packet, _} = ClientRespawn.read(reader)

      assert packet.respawn_type == :same_location
    end

    test "has correct opcode" do
      assert ClientRespawn.opcode() == :client_respawn
    end
  end

  describe "ServerRespawn" do
    test "writes all fields" do
      packet = %ServerRespawn{
        entity_guid: 100,
        position_x: 1.0,
        position_y: 2.0,
        position_z: 3.0,
        health: 500,
        max_health: 500
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerRespawn.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      <<guid::64-little, x::32-float-little, y::32-float-little, z::32-float-little,
        health::32-little, max_health::32-little>> = data

      assert guid == 100
      assert_in_delta x, 1.0, 0.001
      assert_in_delta y, 2.0, 0.001
      assert_in_delta z, 3.0, 0.001
      assert health == 500
      assert max_health == 500
    end

    test "has correct opcode" do
      assert ServerRespawn.opcode() == :server_respawn
    end
  end

  describe "ServerXPGain" do
    test "writes all fields" do
      packet = %ServerXPGain{
        xp_amount: 100,
        source_type: :kill,
        source_guid: 12345,
        current_xp: 500,
        xp_to_level: 1000
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerXPGain.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      <<amount::32-little, source::32-little, source_guid::64-little, current::32-little,
        to_level::32-little>> = data

      assert amount == 100
      assert source == 0
      assert source_guid == 12345
      assert current == 500
      assert to_level == 1000
    end

    test "encodes source types correctly" do
      for {type, expected} <- [kill: 0, quest: 1, exploration: 2] do
        packet = %ServerXPGain{
          xp_amount: 0,
          source_type: type,
          source_guid: 0,
          current_xp: 0,
          xp_to_level: 0
        }

        writer = PacketWriter.new()
        {:ok, writer} = ServerXPGain.write(packet, writer)
        data = PacketWriter.to_binary(writer)

        <<_amount::32-little, source::32-little, _rest::binary>> = data
        assert source == expected
      end
    end

    test "has correct opcode" do
      assert ServerXPGain.opcode() == :server_xp_gain
    end
  end

  describe "ServerLevelUp" do
    test "writes all fields" do
      packet = %ServerLevelUp{
        entity_guid: 100,
        new_level: 10,
        max_health: 280,
        current_xp: 50,
        xp_to_level: 1100
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerLevelUp.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      <<guid::64-little, level::32-little, health::32-little, xp::32-little,
        to_level::32-little>> = data

      assert guid == 100
      assert level == 10
      assert health == 280
      assert xp == 50
      assert to_level == 1100
    end

    test "has correct opcode" do
      assert ServerLevelUp.opcode() == :server_level_up
    end
  end

  describe "ServerLootDrop" do
    test "writes gold and items" do
      packet = %ServerLootDrop{
        source_guid: 12345,
        gold: 50,
        items: [{101, 1}, {102, 2}]
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerLootDrop.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      <<guid::64-little, gold::32-little, item_count::32-little, item1_id::32-little,
        item1_qty::32-little, item2_id::32-little, item2_qty::32-little>> = data

      assert guid == 12345
      assert gold == 50
      assert item_count == 2
      assert item1_id == 101
      assert item1_qty == 1
      assert item2_id == 102
      assert item2_qty == 2
    end

    test "handles empty loot" do
      packet = %ServerLootDrop{
        source_guid: 12345,
        gold: 0,
        items: []
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerLootDrop.write(packet, writer)
      data = PacketWriter.to_binary(writer)

      <<guid::64-little, gold::32-little, item_count::32-little>> = data

      assert guid == 12345
      assert gold == 0
      assert item_count == 0
    end

    test "has correct opcode" do
      assert ServerLootDrop.opcode() == :server_loot_drop
    end
  end
end
