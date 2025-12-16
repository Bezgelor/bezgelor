defmodule BezgelorCore.AICombatMovementTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.AI

  describe "start_chase/3" do
    test "sets chase path and timing" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      path = [{0.0, 0.0, 0.0}, {5.0, 0.0, 0.0}, {10.0, 0.0, 0.0}]
      duration = 2000

      new_ai = AI.start_chase(ai, path, duration)

      assert new_ai.chase_path == path
      assert new_ai.chase_duration == duration
      assert new_ai.chase_start_time != nil
    end

    test "does nothing if not in combat" do
      ai = AI.new({0.0, 0.0, 0.0})

      path = [{0.0, 0.0, 0.0}, {10.0, 0.0, 0.0}]
      new_ai = AI.start_chase(ai, path, 2000)

      assert new_ai.chase_path == nil
    end
  end

  describe "chasing?/1" do
    test "returns true when actively chasing" do
      ai = AI.new({0.0, 0.0, 0.0})
           |> AI.enter_combat(12345)
           |> AI.start_chase([{0.0, 0.0, 0.0}, {10.0, 0.0, 0.0}], 2000)

      assert AI.chasing?(ai) == true
    end

    test "returns false when not chasing" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      assert AI.chasing?(ai) == false
    end
  end

  describe "complete_chase/1" do
    test "clears chase state" do
      ai = AI.new({0.0, 0.0, 0.0})
           |> AI.enter_combat(12345)
           |> AI.start_chase([{0.0, 0.0, 0.0}, {10.0, 0.0, 0.0}], 2000)
           |> AI.complete_chase()

      assert ai.chase_path == nil
      assert ai.chase_start_time == nil
      assert ai.chase_duration == nil
    end
  end

  describe "combat_action/3" do
    test "returns :chase when target is out of attack range" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      target_pos = {20.0, 0.0, 0.0}  # 20 units away
      attack_range = 5.0              # Melee range

      result = AI.combat_action(ai, target_pos, attack_range)

      assert result == {:chase, target_pos}
    end

    test "returns :attack when target is in attack range" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      target_pos = {3.0, 0.0, 0.0}  # 3 units away
      attack_range = 5.0             # Within melee range

      result = AI.combat_action(ai, target_pos, attack_range)

      assert result == {:attack, 12345}
    end

    test "returns :none when not in combat" do
      ai = AI.new({0.0, 0.0, 0.0})

      result = AI.combat_action(ai, {5.0, 0.0, 0.0}, 5.0)

      assert result == :none
    end
  end
end
