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
      # Verify data was written (format is bit-packed so exact structure varies)
      assert byte_size(data) > 0
    end

    test "writes character list with single character" do
      character = %CharacterEntry{
        id: 1,
        name: "TestChar",
        sex: 0,
        race: 0,
        class: 0,
        path: 0,
        faction: 166,
        level: 50,
        world_id: 1,
        world_zone_id: 100,
        last_logged_out_days: 0.0
      }

      packet = %ServerCharacterList{
        characters: [character],
        max_characters: 12
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterList.write(packet, writer)

      data = PacketWriter.to_binary(writer)
      # Just verify it produces data without crashing
      assert byte_size(data) > 0
    end

    test "writes character with customization data" do
      character = %CharacterEntry{
        id: 2,
        name: "Styled",
        sex: 1,
        race: 4,
        class: 2,
        path: 1,
        faction: 166,
        level: 25,
        world_id: 2,
        world_zone_id: 200,
        last_logged_out_days: 5.5,
        labels: [100, 101, 102],
        values: [1, 2, 3],
        bones: [1.0, 2.0, 3.0]
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

    test "writes multiple characters" do
      characters = [
        %CharacterEntry{
          id: 1,
          name: "First",
          sex: 0,
          race: 0,
          class: 0,
          path: 0,
          faction: 166,
          level: 10,
          world_id: 1,
          world_zone_id: 1,
          last_logged_out_days: 0.0
        },
        %CharacterEntry{
          id: 2,
          name: "Second",
          sex: 1,
          race: 4,
          class: 2,
          path: 1,
          faction: 166,
          level: 20,
          world_id: 1,
          world_zone_id: 2,
          last_logged_out_days: 1.0
        }
      ]

      packet = %ServerCharacterList{
        characters: characters,
        max_characters: 12
      }

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterList.write(packet, writer)

      data = PacketWriter.to_binary(writer)
      assert byte_size(data) > 0
    end

    test "handles gear data" do
      character = %CharacterEntry{
        id: 1,
        name: "Geared",
        sex: 0,
        race: 0,
        class: 0,
        path: 0,
        faction: 166,
        level: 50,
        world_id: 1,
        world_zone_id: 1,
        last_logged_out_days: 0.0,
        gear: [
          %ServerCharacterList.ItemVisual{slot: 0, display_id: 100, colour_set_id: 1, dye_data: 0},
          %ServerCharacterList.ItemVisual{slot: 1, display_id: 200, colour_set_id: 2, dye_data: 0}
        ],
        gear_mask: 3
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

  describe "CharacterEntry struct" do
    test "has correct default values" do
      entry = %CharacterEntry{
        id: 1,
        name: "Test",
        sex: 0,
        race: 0,
        class: 0,
        faction: 166,
        level: 1
      }

      assert entry.world_id == 0
      assert entry.world_zone_id == 0
      assert entry.path == 0
      assert entry.is_locked == false
      assert entry.requires_rename == false
      assert entry.gear_mask == 0
      assert entry.labels == []
      assert entry.values == []
      assert entry.bones == []
      assert entry.last_logged_out_days == 0.0
    end
  end

  describe "ItemVisual struct" do
    test "has correct default values" do
      visual = %ServerCharacterList.ItemVisual{}

      assert visual.slot == 0
      assert visual.display_id == 0
      assert visual.colour_set_id == 0
      assert visual.dye_data == 0
    end
  end

  describe "Identity struct" do
    test "has correct default values" do
      identity = %ServerCharacterList.Identity{}

      assert identity.realm_id == 0
      assert identity.id == 0
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
          last_online: nil
        }
      ]

      packet = ServerCharacterList.from_characters(db_characters)

      assert packet.max_characters == 12
      assert length(packet.characters) == 1

      [entry] = packet.characters
      assert entry.id == 100
      assert entry.name == "DBChar"
      assert entry.path == 2
      assert entry.world_zone_id == 50
    end

    test "builds packet with custom max characters" do
      packet = ServerCharacterList.from_characters([], 24)
      assert packet.max_characters == 24
    end
  end
end
