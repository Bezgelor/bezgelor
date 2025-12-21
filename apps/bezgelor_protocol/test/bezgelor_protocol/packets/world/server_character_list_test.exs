defmodule BezgelorProtocol.Packets.World.ServerCharacterListTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ServerCharacterList
  alias BezgelorProtocol.Packets.World.ServerCharacterList.CharacterEntry
  alias BezgelorProtocol.PacketWriter

  describe "opcode/0" do
    test "returns the correct opcode" do
      assert ServerCharacterList.opcode() == :server_character_list
    end
  end

  describe "write/2" do
    test "writes empty character list" do
      packet = %ServerCharacterList{
        characters: [],
        max_characters: 12
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterList.write(packet, writer)

      data = PacketWriter.to_binary(writer)

      # max_characters (4 bytes) + character_count (4 bytes)
      assert <<12::little-32, 0::little-32>> = data
    end

    test "writes character list with single character" do
      character = %CharacterEntry{
        id: 1,
        name: "TestChar",
        sex: 0,
        race: 0,
        class: 0,
        path: 0,
        faction_id: 166,
        level: 50,
        world_id: 1,
        zone_id: 100,
        last_login: 1_700_000_000,
        appearance: nil
      }

      packet = %ServerCharacterList{
        characters: [character],
        max_characters: 12
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterList.write(packet, writer)

      data = PacketWriter.to_binary(writer)

      # Parse header
      <<max_chars::little-32, count::little-32, rest::binary>> = data
      assert max_chars == 12
      assert count == 1

      # Parse character ID
      <<char_id::little-64, rest::binary>> = rest
      assert char_id == 1

      # Parse name (wide string: length + UTF-16LE)
      <<name_len::little-32, name_bytes::binary-size(16), rest::binary>> = rest
      assert name_len == 8
      name = :unicode.characters_to_binary(name_bytes, {:utf16, :little}, :utf8)
      assert name == "TestChar"

      # Parse numeric fields
      <<sex::little-32, race::little-32, class::little-32, path::little-32, faction::little-32,
        level::little-32, world_id::little-32, zone_id::little-32, last_login::little-64,
        _rest::binary>> = rest

      assert sex == 0
      assert race == 0
      assert class == 0
      assert path == 0
      assert faction == 166
      assert level == 50
      assert world_id == 1
      assert zone_id == 100
      assert last_login == 1_700_000_000
    end

    test "writes character with appearance data" do
      appearance = %{
        body_type: 1,
        body_height: 2,
        body_weight: 3,
        face_type: 4,
        eye_type: 5,
        eye_color: 6,
        nose_type: 7,
        mouth_type: 8,
        ear_type: 9,
        hair_style: 10,
        hair_color: 11,
        facial_hair: 12,
        skin_color: 13,
        feature_1: 14,
        feature_2: 15,
        feature_3: 16,
        feature_4: 17,
        bones: [1.0, 2.0, 3.0]
      }

      character = %CharacterEntry{
        id: 2,
        name: "Styled",
        sex: 1,
        race: 4,
        class: 2,
        path: 1,
        faction_id: 166,
        level: 25,
        world_id: 2,
        zone_id: 200,
        last_login: nil,
        appearance: appearance
      }

      packet = %ServerCharacterList{
        characters: [character],
        max_characters: 12
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterList.write(packet, writer)

      data = PacketWriter.to_binary(writer)
      # Just verify it doesn't crash and produces data
      assert byte_size(data) > 0
    end

    test "writes multiple characters" do
      characters = [
        %CharacterEntry{
          id: 1,
          name: "First",
          sex: 0,
          race: 0,
          class: 0,
          path: 0,
          faction_id: 166,
          level: 10,
          world_id: 1,
          zone_id: 1,
          last_login: nil,
          appearance: nil
        },
        %CharacterEntry{
          id: 2,
          name: "Second",
          sex: 1,
          race: 4,
          class: 2,
          path: 1,
          faction_id: 166,
          level: 20,
          world_id: 1,
          zone_id: 2,
          last_login: nil,
          appearance: nil
        }
      ]

      packet = %ServerCharacterList{
        characters: characters,
        max_characters: 12
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterList.write(packet, writer)

      data = PacketWriter.to_binary(writer)

      <<max_chars::little-32, count::little-32, _rest::binary>> = data
      assert max_chars == 12
      assert count == 2
    end

    test "handles DateTime last_login" do
      {:ok, datetime, _} = DateTime.from_iso8601("2024-01-01T12:00:00Z")

      character = %CharacterEntry{
        id: 1,
        name: "DateTime",
        sex: 0,
        race: 0,
        class: 0,
        path: 0,
        faction_id: 166,
        level: 1,
        world_id: 1,
        zone_id: 1,
        last_login: datetime,
        appearance: nil
      }

      packet = %ServerCharacterList{
        characters: [character],
        max_characters: 12
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterList.write(packet, writer)

      data = PacketWriter.to_binary(writer)
      assert byte_size(data) > 0
    end
  end

  describe "from_characters/2" do
    test "builds packet from database characters" do
      db_characters = [
        %{
          id: 100,
          name: "DBChar",
          sex: 0,
          race: 0,
          class: 0,
          active_path: 2,
          faction_id: 166,
          level: 30,
          world_id: 1,
          world_zone_id: 50,
          last_online: nil,
          appearance: nil
        }
      ]

      packet = ServerCharacterList.from_characters(db_characters)

      assert packet.max_characters == 12
      assert length(packet.characters) == 1

      [entry] = packet.characters
      assert entry.id == 100
      assert entry.name == "DBChar"
      assert entry.path == 2
      assert entry.zone_id == 50
    end

    test "builds packet with custom max characters" do
      packet = ServerCharacterList.from_characters([], 24)
      assert packet.max_characters == 24
    end
  end
end
