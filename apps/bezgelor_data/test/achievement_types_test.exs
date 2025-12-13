defmodule BezgelorData.AchievementTypesTest do
  use ExUnit.Case, async: true

  alias BezgelorData.AchievementTypes

  describe "event_type/1" do
    test "maps kill achievement types" do
      assert AchievementTypes.event_type(2) == :kill
      assert AchievementTypes.event_type(61) == :kill
      assert AchievementTypes.event_type(105) == :kill
    end

    test "maps quest achievement types" do
      assert AchievementTypes.event_type(35) == :quest_complete
      assert AchievementTypes.event_type(77) == :quest_complete
    end

    test "maps zone exploration types" do
      assert AchievementTypes.event_type(5) == :zone_explore
      assert AchievementTypes.event_type(8) == :zone_explore
      assert AchievementTypes.event_type(12) == :zone_explore
      assert AchievementTypes.event_type(121) == :zone_explore
    end

    test "maps dungeon/instance types" do
      assert AchievementTypes.event_type(6) == :dungeon_complete
      assert AchievementTypes.event_type(7) == :dungeon_complete
      assert AchievementTypes.event_type(38) == :dungeon_complete
      assert AchievementTypes.event_type(80) == :dungeon_complete
    end

    test "maps path mission types" do
      assert AchievementTypes.event_type(37) == :path_mission
      assert AchievementTypes.event_type(40) == :path_mission
      assert AchievementTypes.event_type(96) == :path_mission
    end

    test "maps tradeskill types" do
      assert AchievementTypes.event_type(87) == :tradeskill
      assert AchievementTypes.event_type(88) == :tradeskill
      assert AchievementTypes.event_type(94) == :tradeskill
      assert AchievementTypes.event_type(102) == :tradeskill
    end

    test "maps challenge types" do
      assert AchievementTypes.event_type(44) == :challenge_complete
      assert AchievementTypes.event_type(45) == :challenge_complete
    end

    test "maps pvp types" do
      assert AchievementTypes.event_type(33) == :pvp
      assert AchievementTypes.event_type(76) == :pvp
    end

    test "maps datacube/lore types" do
      assert AchievementTypes.event_type(1) == :datacube
      assert AchievementTypes.event_type(15) == :datacube
      assert AchievementTypes.event_type(46) == :datacube
      assert AchievementTypes.event_type(82) == :datacube
    end

    test "maps event types" do
      assert AchievementTypes.event_type(57) == :event
      assert AchievementTypes.event_type(116) == :event
      assert AchievementTypes.event_type(137) == :event
    end

    test "maps social/economy types" do
      assert AchievementTypes.event_type(9) == :social
      assert AchievementTypes.event_type(63) == :social
    end

    test "maps housing types" do
      assert AchievementTypes.event_type(53) == :housing
      assert AchievementTypes.event_type(65) == :housing
    end

    test "maps adventure types" do
      assert AchievementTypes.event_type(42) == :adventure_complete
      assert AchievementTypes.event_type(67) == :adventure_complete
    end

    test "maps meta achievement types" do
      assert AchievementTypes.event_type(104) == :meta
      assert AchievementTypes.event_type(141) == :meta
    end

    test "maps progression types" do
      assert AchievementTypes.event_type(3) == :progression
      assert AchievementTypes.event_type(13) == :progression
      assert AchievementTypes.event_type(16) == :progression
    end

    test "maps mount types" do
      assert AchievementTypes.event_type(72) == :mount
      assert AchievementTypes.event_type(86) == :mount
    end

    test "returns nil for unknown types" do
      assert AchievementTypes.event_type(9999) == nil
      assert AchievementTypes.event_type(0) == nil
      assert AchievementTypes.event_type(-1) == nil
    end
  end

  describe "uses_object_id?/1" do
    test "returns true for types that track specific objects" do
      # Type 2 (kill specific creature) uses objectId
      assert AchievementTypes.uses_object_id?(2) == true
      # Type 35 (complete specific quest) uses objectId
      assert AchievementTypes.uses_object_id?(35) == true
      # Type 1 (find specific datacube) uses objectId
      assert AchievementTypes.uses_object_id?(1) == true
    end

    test "returns false for counter types" do
      # Type 61 (kill X creatures) is a counter
      assert AchievementTypes.uses_object_id?(61) == false
      # Type 105 (kill elite creatures) is a counter
      assert AchievementTypes.uses_object_id?(105) == false
    end
  end

  describe "uses_counter?/1" do
    test "returns true for counter-based types" do
      assert AchievementTypes.uses_counter?(61) == true  # Kill X creatures
      assert AchievementTypes.uses_counter?(77) == true  # Complete X quests
      assert AchievementTypes.uses_counter?(88) == true  # Craft X items
      assert AchievementTypes.uses_counter?(33) == true  # Win X PvP matches
    end

    test "returns false for specific-target types" do
      assert AchievementTypes.uses_counter?(2) == false  # Kill specific creature
      assert AchievementTypes.uses_counter?(35) == false # Complete specific quest
    end
  end

  describe "types_for_event/1" do
    test "returns kill type IDs" do
      assert AchievementTypes.types_for_event(:kill) == [2, 61, 105]
    end

    test "returns quest type IDs" do
      assert AchievementTypes.types_for_event(:quest_complete) == [35, 77]
    end

    test "returns zone exploration type IDs" do
      assert AchievementTypes.types_for_event(:zone_explore) == [5, 8, 12, 121]
    end

    test "returns empty list for unknown event" do
      assert AchievementTypes.types_for_event(:unknown) == []
    end
  end

  describe "all_event_types/0" do
    test "returns all supported event types" do
      types = AchievementTypes.all_event_types()

      assert :kill in types
      assert :quest_complete in types
      assert :zone_explore in types
      assert :dungeon_complete in types
      assert :path_mission in types
      assert :tradeskill in types
      assert :challenge_complete in types
      assert :pvp in types
      assert :datacube in types
      assert :event in types
      assert :social in types
      assert :housing in types
      assert :adventure_complete in types
      assert :meta in types
      assert :progression in types
      assert :mount in types
    end

    test "returns 16 event types" do
      assert length(AchievementTypes.all_event_types()) == 16
    end
  end

  describe "points_for_enum/1" do
    test "maps point enum values correctly" do
      assert AchievementTypes.points_for_enum(0) == 0
      assert AchievementTypes.points_for_enum(1) == 5
      assert AchievementTypes.points_for_enum(2) == 10
      assert AchievementTypes.points_for_enum(3) == 25
    end

    test "returns 0 for invalid enum values" do
      assert AchievementTypes.points_for_enum(4) == 0
      assert AchievementTypes.points_for_enum(-1) == 0
      assert AchievementTypes.points_for_enum(100) == 0
    end
  end
end
