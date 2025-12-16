defmodule BezgelorProtocol.Packets.World.ServerPlayerDeathTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerPlayerDeath
  alias BezgelorProtocol.PacketWriter

  describe "write/2" do
    test "writes player death packet with killer" do
      packet = %ServerPlayerDeath{
        player_guid: 0x1000000000000001,
        killer_guid: 0x0400000000000002,
        death_type: 0
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerPlayerDeath.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # player_guid: 8 bytes
      # killer_guid: 8 bytes
      # death_type: 4 bytes
      assert byte_size(binary) == 20
    end

    test "writes player death packet without killer (environmental)" do
      packet = %ServerPlayerDeath{
        player_guid: 0x1000000000000001,
        killer_guid: nil,
        death_type: 1
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerPlayerDeath.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      # killer_guid should be 0 when nil
      <<_player_guid::little-64, killer_guid::little-64, _death_type::little-32>> = binary
      assert killer_guid == 0
    end

    test "serializes combat death type correctly" do
      packet = %ServerPlayerDeath{
        player_guid: 0x1000000000000001,
        killer_guid: 0x0400000000000002,
        death_type: 0
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerPlayerDeath.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_player::little-64, _killer::little-64, death_type::little-32>> = binary
      assert death_type == 0
    end

    test "serializes fall death type correctly" do
      packet = %ServerPlayerDeath{
        player_guid: 0x1000000000000001,
        killer_guid: nil,
        death_type: 1
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerPlayerDeath.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_player::little-64, _killer::little-64, death_type::little-32>> = binary
      assert death_type == 1
    end

    test "serializes drown death type correctly" do
      packet = %ServerPlayerDeath{
        player_guid: 0x1000000000000001,
        killer_guid: nil,
        death_type: 2
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerPlayerDeath.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_player::little-64, _killer::little-64, death_type::little-32>> = binary
      assert death_type == 2
    end

    test "serializes environment death type correctly" do
      packet = %ServerPlayerDeath{
        player_guid: 0x1000000000000001,
        killer_guid: nil,
        death_type: 3
      }

      writer = PacketWriter.new()
      {:ok, writer} = ServerPlayerDeath.write(packet, writer)
      binary = PacketWriter.to_binary(writer)

      <<_player::little-64, _killer::little-64, death_type::little-32>> = binary
      assert death_type == 3
    end
  end

  describe "new/3" do
    test "creates packet with correct values" do
      packet = ServerPlayerDeath.new(0x1000000000000001, 0x0400000000000002, :combat)

      assert packet.player_guid == 0x1000000000000001
      assert packet.killer_guid == 0x0400000000000002
      assert packet.death_type == 0
    end

    test "converts death type atom to integer" do
      assert ServerPlayerDeath.new(1, 2, :combat).death_type == 0
      assert ServerPlayerDeath.new(1, 2, :fall).death_type == 1
      assert ServerPlayerDeath.new(1, 2, :drown).death_type == 2
      assert ServerPlayerDeath.new(1, 2, :environment).death_type == 3
    end
  end

  describe "opcode/0" do
    test "returns correct opcode" do
      assert ServerPlayerDeath.opcode() == :server_player_death
    end
  end
end
