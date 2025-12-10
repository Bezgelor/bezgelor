defmodule BezgelorProtocol.Packets.World.CharacterManagementTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Packets.World.ClientCharacterSelect
  alias BezgelorProtocol.Packets.World.ClientCharacterCreate
  alias BezgelorProtocol.Packets.World.ClientCharacterCreate.Appearance
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

    test "read/1 parses character creation request" do
      payload = build_create_packet("TestHero", 0, 0, 0, 2, default_appearance())
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientCharacterCreate.read(reader)
      assert packet.name == "TestHero"
      assert packet.sex == 0
      assert packet.race == 0
      assert packet.class == 0
      assert packet.path == 2
      assert packet.appearance != nil
    end

    test "read/1 parses appearance data" do
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
        bones: [0.5, 1.0, -0.5]
      }

      payload = build_create_packet("Styled", 1, 4, 2, 1, appearance)
      reader = PacketReader.new(payload)

      assert {:ok, packet, _reader} = ClientCharacterCreate.read(reader)
      assert packet.appearance.body_type == 1
      assert packet.appearance.hair_style == 10
      assert packet.appearance.skin_color == 13
      assert length(packet.appearance.bones) == 3
    end

    test "appearance_to_map/1 converts appearance to map" do
      appearance = %Appearance{
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
        bones: [1.0, 2.0]
      }

      map = ClientCharacterCreate.appearance_to_map(appearance)
      assert map.body_type == 1
      assert map.hair_style == 10
      assert map.bones == [1.0, 2.0]
    end
  end

  describe "ServerCharacterCreate" do
    test "opcode/0 returns correct opcode" do
      assert ServerCharacterCreate.opcode() == :server_character_create
    end

    test "write/2 writes success response" do
      packet = ServerCharacterCreate.success(12345)

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterCreate.write(packet, writer)

      data = PacketWriter.to_binary(writer)
      <<result::little-32, char_id::little-64>> = data

      assert result == 0
      assert char_id == 12345
    end

    test "write/2 writes failure response" do
      packet = ServerCharacterCreate.failure(:name_taken)

      writer = PacketWriter.new()
      assert {:ok, writer} = ServerCharacterCreate.write(packet, writer)

      data = PacketWriter.to_binary(writer)
      <<result::little-32, char_id::little-64>> = data

      assert result == 1
      assert char_id == 0
    end

    test "result_to_code/1 converts all results" do
      assert ServerCharacterCreate.result_to_code(:success) == 0
      assert ServerCharacterCreate.result_to_code(:name_taken) == 1
      assert ServerCharacterCreate.result_to_code(:invalid_name) == 2
      assert ServerCharacterCreate.result_to_code(:max_characters) == 3
      assert ServerCharacterCreate.result_to_code(:invalid_race) == 4
      assert ServerCharacterCreate.result_to_code(:invalid_class) == 5
      assert ServerCharacterCreate.result_to_code(:invalid_faction) == 6
      assert ServerCharacterCreate.result_to_code(:server_error) == 7
    end

    test "code_to_result/1 converts all codes" do
      assert ServerCharacterCreate.code_to_result(0) == :success
      assert ServerCharacterCreate.code_to_result(1) == :name_taken
      assert ServerCharacterCreate.code_to_result(2) == :invalid_name
      assert ServerCharacterCreate.code_to_result(3) == :max_characters
      assert ServerCharacterCreate.code_to_result(4) == :invalid_race
      assert ServerCharacterCreate.code_to_result(5) == :invalid_class
      assert ServerCharacterCreate.code_to_result(6) == :invalid_faction
      assert ServerCharacterCreate.code_to_result(99) == :server_error
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

  # Helper functions

  defp build_create_packet(name, sex, race, class, path, appearance) do
    utf16_name = :unicode.characters_to_binary(name, :utf8, {:utf16, :little})
    name_length = String.length(name)

    <<
      name_length::little-32,
      utf16_name::binary,
      sex::little-32,
      race::little-32,
      class::little-32,
      path::little-32
    >> <> build_appearance(appearance)
  end

  defp build_appearance(appearance) do
    bones = Map.get(appearance, :bones, [])
    bone_count = length(bones)

    bone_data =
      bones
      |> Enum.map(fn b -> <<b::little-float-32>> end)
      |> Enum.join()

    <<
      Map.get(appearance, :body_type, 0)::little-32,
      Map.get(appearance, :body_height, 0)::little-32,
      Map.get(appearance, :body_weight, 0)::little-32,
      Map.get(appearance, :face_type, 0)::little-32,
      Map.get(appearance, :eye_type, 0)::little-32,
      Map.get(appearance, :eye_color, 0)::little-32,
      Map.get(appearance, :nose_type, 0)::little-32,
      Map.get(appearance, :mouth_type, 0)::little-32,
      Map.get(appearance, :ear_type, 0)::little-32,
      Map.get(appearance, :hair_style, 0)::little-32,
      Map.get(appearance, :hair_color, 0)::little-32,
      Map.get(appearance, :facial_hair, 0)::little-32,
      Map.get(appearance, :skin_color, 0)::little-32,
      Map.get(appearance, :feature_1, 0)::little-32,
      Map.get(appearance, :feature_2, 0)::little-32,
      Map.get(appearance, :feature_3, 0)::little-32,
      Map.get(appearance, :feature_4, 0)::little-32,
      bone_count::little-32
    >> <> bone_data
  end

  defp default_appearance do
    %{
      body_type: 0,
      body_height: 0,
      body_weight: 0,
      face_type: 0,
      eye_type: 0,
      eye_color: 0,
      nose_type: 0,
      mouth_type: 0,
      ear_type: 0,
      hair_style: 0,
      hair_color: 0,
      facial_hair: 0,
      skin_color: 0,
      feature_1: 0,
      feature_2: 0,
      feature_3: 0,
      feature_4: 0,
      bones: []
    }
  end
end
