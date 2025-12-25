defmodule BezgelorProtocol.Packets.World.CharacterManagementTest do
  @moduledoc """
  Unit tests for character management packets.

  Note: Packet parsing tests are omitted as they require complex bit-packing
  that matches NexusForever's GamePacketReader implementation. The module
  functions are tested directly instead.
  """
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ClientCharacterSelect
  alias BezgelorProtocol.Packets.World.ClientCharacterCreate
  alias BezgelorProtocol.Packets.World.ServerCharacterCreate
  alias BezgelorProtocol.Packets.World.ClientCharacterDelete
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter

  describe "ClientCharacterSelect" do
    test "opcode/0 returns correct opcode" do
      assert ClientCharacterSelect.opcode() == :client_character_select
    end

    test "read/1 parses character ID" do
      character_id = 123_456_789
      payload = <<character_id::little-64>>
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientCharacterSelect.read(reader)
      assert packet.character_id == character_id
    end

    test "read/1 handles large character IDs" do
      character_id = 18_446_744_073_709_551_615
      payload = <<character_id::little-64>>
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientCharacterSelect.read(reader)
      assert packet.character_id == character_id
    end

    test "read/1 returns error on truncated data" do
      payload = <<1, 2, 3, 4>>
      reader = PacketReader.new(payload)

      assert {:error, :eof} = ClientCharacterSelect.read(reader)
    end
  end

  describe "ClientCharacterCreate" do
    test "opcode/0 returns correct opcode" do
      assert ClientCharacterCreate.opcode() == :client_character_create
    end

    test "struct has correct fields" do
      packet = %ClientCharacterCreate{
        character_creation_id: 42,
        name: "TestHero",
        path: 2,
        labels: [100, 101],
        values: [1, 2],
        bones: [0.5, 1.0]
      }

      assert packet.character_creation_id == 42
      assert packet.name == "TestHero"
      assert packet.path == 2
      assert packet.labels == [100, 101]
      assert packet.values == [1, 2]
      assert packet.bones == [0.5, 1.0]
    end

    test "struct has default empty lists" do
      packet = %ClientCharacterCreate{
        character_creation_id: 1,
        name: "Default",
        path: 0
      }

      assert packet.labels == []
      assert packet.values == []
      assert packet.bones == []
    end

    test "customization_to_map/1 converts packet to map" do
      packet = %ClientCharacterCreate{
        character_creation_id: 42,
        name: "Test",
        path: 1,
        labels: [100, 101, 102],
        values: [1, 2, 3],
        bones: [0.5, 1.0]
      }

      map = ClientCharacterCreate.customization_to_map(packet)
      assert map.labels == [100, 101, 102]
      assert map.values == [1, 2, 3]
      assert map.bones == [0.5, 1.0]
      assert map.customizations == %{100 => 1, 101 => 2, 102 => 3}
    end

    test "customization_to_map/1 handles empty customizations" do
      packet = %ClientCharacterCreate{
        character_creation_id: 1,
        name: "Empty",
        path: 0,
        labels: [],
        values: [],
        bones: []
      }

      map = ClientCharacterCreate.customization_to_map(packet)
      assert map.labels == []
      assert map.values == []
      assert map.bones == []
      assert map.customizations == %{}
    end

    test "customization_to_map/1 handles single customization" do
      packet = %ClientCharacterCreate{
        character_creation_id: 10,
        name: "Single",
        path: 0,
        labels: [200],
        values: [50],
        bones: []
      }

      map = ClientCharacterCreate.customization_to_map(packet)
      assert map.customizations == %{200 => 50}
    end
  end

  describe "ServerCharacterCreate" do
    test "opcode/0 returns correct opcode" do
      assert ServerCharacterCreate.opcode() == :server_character_create
    end

    test "success/1 creates success response with character ID" do
      packet = ServerCharacterCreate.success(12345)

      assert packet.result == :success
      assert packet.character_id == 12345
      assert packet.world_id == 870
    end

    test "success/2 creates success response with character ID and world ID" do
      packet = ServerCharacterCreate.success(12345, 999)

      assert packet.result == :success
      assert packet.character_id == 12345
      assert packet.world_id == 999
    end

    test "failure/1 creates failure response" do
      packet = ServerCharacterCreate.failure(:name_taken)

      assert packet.result == :name_taken
      assert packet.character_id == 0
      assert packet.world_id == 0
    end

    test "failure/1 with various reasons" do
      for reason <- [:invalid_name, :max_characters, :invalid_faction, :server_error] do
        packet = ServerCharacterCreate.failure(reason)
        assert packet.result == reason
      end
    end

    test "write/2 writes success response" do
      packet = ServerCharacterCreate.success(12345)

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterCreate.write(packet, writer)

      data = PacketWriter.to_binary(writer)
      # Format: character_id (8 bytes) + world_id (4 bytes) + result (3 bits padded to 1 byte)
      assert byte_size(data) == 13

      <<char_id::little-64, world_id::little-32, _result_byte::8>> = data
      assert char_id == 12345
      assert world_id == 870
    end

    test "write/2 writes failure response" do
      packet = ServerCharacterCreate.failure(:name_taken)

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterCreate.write(packet, writer)

      data = PacketWriter.to_binary(writer)
      assert byte_size(data) == 13

      <<char_id::little-64, world_id::little-32, _result_byte::8>> = data
      assert char_id == 0
      assert world_id == 0
    end

    test "result_to_code/1 converts success" do
      # CharacterModifyResult.CreateOk = 0x03
      assert ServerCharacterCreate.result_to_code(:success) == 0x03
    end

    test "result_to_code/1 converts name_taken" do
      # CharacterModifyResult.CreateFailed_UniqueName = 0x06
      assert ServerCharacterCreate.result_to_code(:name_taken) == 0x06
    end

    test "result_to_code/1 converts invalid_name" do
      # CharacterModifyResult.CreateFailed_InvalidName = 0x0A
      assert ServerCharacterCreate.result_to_code(:invalid_name) == 0x0A
    end

    test "result_to_code/1 converts max_characters" do
      # CharacterModifyResult.CreateFailed_AccountFull = 0x09
      assert ServerCharacterCreate.result_to_code(:max_characters) == 0x09
    end

    test "result_to_code/1 converts invalid_faction" do
      # CharacterModifyResult.CreateFailed_Faction = 0x0B
      assert ServerCharacterCreate.result_to_code(:invalid_faction) == 0x0B
    end

    test "result_to_code/1 converts server_error" do
      # CharacterModifyResult.CreateFailed_Internal = 0x0C
      assert ServerCharacterCreate.result_to_code(:server_error) == 0x0C
    end

    test "result_to_code/1 defaults unknown to internal error" do
      assert ServerCharacterCreate.result_to_code(:unknown_reason) == 0x0C
    end
  end

  describe "ClientCharacterDelete" do
    test "opcode/0 returns correct opcode" do
      assert ClientCharacterDelete.opcode() == :client_character_delete
    end

    test "read/1 parses character ID" do
      character_id = 987_654
      payload = <<character_id::little-64>>
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientCharacterDelete.read(reader)
      assert packet.character_id == character_id
    end

    test "read/1 returns error on truncated data" do
      payload = <<1, 2>>
      reader = PacketReader.new(payload)

      assert {:error, :eof} = ClientCharacterDelete.read(reader)
    end
  end
end
