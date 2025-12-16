defmodule BezgelorCore.AICombatMovementTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.AI

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
