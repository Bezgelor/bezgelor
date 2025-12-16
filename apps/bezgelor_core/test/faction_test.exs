defmodule BezgelorCore.FactionTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.Faction

  describe "hostile?/2" do
    test "exile and dominion are hostile" do
      assert Faction.hostile?(:exile, :dominion)
      assert Faction.hostile?(:dominion, :exile)
    end

    test "same faction is not hostile" do
      refute Faction.hostile?(:exile, :exile)
      refute Faction.hostile?(:dominion, :dominion)
    end

    test "hostile creatures are hostile to players" do
      assert Faction.hostile?(:hostile, :exile)
      assert Faction.hostile?(:hostile, :dominion)
    end

    test "neutral creatures are not hostile" do
      refute Faction.hostile?(:neutral, :exile)
      refute Faction.hostile?(:neutral, :dominion)
    end

    test "friendly creatures are not hostile" do
      refute Faction.hostile?(:friendly, :exile)
      refute Faction.hostile?(:friendly, :dominion)
    end
  end

  describe "faction_from_id/1" do
    test "maps known faction IDs" do
      assert Faction.faction_from_id(166) == :exile
      assert Faction.faction_from_id(167) == :dominion
      assert Faction.faction_from_id(0) == :neutral
    end

    test "unknown IDs default to neutral" do
      assert Faction.faction_from_id(99999) == :neutral
    end

    test "hostile faction IDs are recognized" do
      assert Faction.faction_from_id(281) == :hostile
      assert Faction.faction_from_id(282) == :hostile
    end
  end

  describe "creature_hostile_to_player?/2" do
    test "hostile creature is hostile to any player" do
      assert Faction.creature_hostile_to_player?(281, :exile)
      assert Faction.creature_hostile_to_player?(282, :dominion)
    end

    test "neutral creature is not hostile to any player" do
      refute Faction.creature_hostile_to_player?(0, :exile)
      refute Faction.creature_hostile_to_player?(0, :dominion)
    end
  end
end
