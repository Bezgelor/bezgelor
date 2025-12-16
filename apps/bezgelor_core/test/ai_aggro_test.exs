defmodule BezgelorCore.AIAggroTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.AI

  describe "check_aggro_with_faction/4" do
    test "only aggros hostile faction players" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 11111, position: {5.0, 0.0, 0.0}, faction: :exile},
        %{guid: 22222, position: {6.0, 0.0, 0.0}, faction: :dominion}
      ]

      # Creature is hostile faction - aggros both (takes closest)
      result = AI.check_aggro_with_faction(ai, nearby_players, 10.0, :hostile)
      assert result == {:aggro, 11111}
    end

    test "friendly creatures don't aggro" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 12345, position: {5.0, 0.0, 0.0}, faction: :exile}
      ]

      result = AI.check_aggro_with_faction(ai, nearby_players, 10.0, :friendly)
      assert result == nil
    end

    test "neutral creatures don't aggro" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 12345, position: {5.0, 0.0, 0.0}, faction: :exile}
      ]

      result = AI.check_aggro_with_faction(ai, nearby_players, 10.0, :neutral)
      assert result == nil
    end

    test "exile creature only aggros dominion players" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 11111, position: {5.0, 0.0, 0.0}, faction: :exile},  # Same faction
        %{guid: 22222, position: {6.0, 0.0, 0.0}, faction: :dominion}  # Enemy
      ]

      result = AI.check_aggro_with_faction(ai, nearby_players, 10.0, :exile)
      assert result == {:aggro, 22222}
    end

    test "returns nil when no hostile players in range" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 11111, position: {5.0, 0.0, 0.0}, faction: :exile}
      ]

      # Exile creature won't aggro exile players
      result = AI.check_aggro_with_faction(ai, nearby_players, 10.0, :exile)
      assert result == nil
    end
  end

  describe "check_aggro/3" do
    test "returns target when player in aggro range" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 12345, position: {5.0, 0.0, 0.0}}  # 5 units away
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == {:aggro, 12345}
    end

    test "returns nil when no players in range" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 12345, position: {50.0, 0.0, 0.0}}  # 50 units away
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == nil
    end

    test "returns nil when already in combat" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(99999)

      nearby_players = [
        %{guid: 12345, position: {5.0, 0.0, 0.0}}
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == nil
    end

    test "returns closest player when multiple in range" do
      ai = AI.new({0.0, 0.0, 0.0})

      nearby_players = [
        %{guid: 11111, position: {8.0, 0.0, 0.0}},  # 8 units
        %{guid: 22222, position: {3.0, 0.0, 0.0}},  # 3 units (closest)
        %{guid: 33333, position: {6.0, 0.0, 0.0}}   # 6 units
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == {:aggro, 22222}
    end

    test "returns nil when evading" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.start_evade()

      nearby_players = [
        %{guid: 12345, position: {5.0, 0.0, 0.0}}
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == nil
    end

    test "returns nil when dead" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.set_dead()

      nearby_players = [
        %{guid: 12345, position: {5.0, 0.0, 0.0}}
      ]

      result = AI.check_aggro(ai, nearby_players, 10.0)

      assert result == nil
    end

    test "returns nil with empty player list" do
      ai = AI.new({0.0, 0.0, 0.0})

      result = AI.check_aggro(ai, [], 10.0)

      assert result == nil
    end
  end
end
