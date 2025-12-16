defmodule BezgelorCore.AIAggroTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.AI

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
