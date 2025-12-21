defmodule BezgelorCore.AILeashTest do
  use ExUnit.Case, async: true

  alias BezgelorCore.AI

  describe "check_leash/3" do
    test "returns :evade when current position exceeds leash range" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      # Creature moved 50 units from spawn (leash range 40)
      current_pos = {50.0, 0.0, 0.0}

      result = AI.check_leash(ai, current_pos, 40.0)

      assert result == :evade
    end

    test "returns :ok when within leash range" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      # Creature 30 units from spawn (within 40 leash range)
      current_pos = {30.0, 0.0, 0.0}

      result = AI.check_leash(ai, current_pos, 40.0)

      assert result == :ok
    end

    test "returns :ok when not in combat" do
      ai = AI.new({0.0, 0.0, 0.0})

      current_pos = {100.0, 0.0, 0.0}

      result = AI.check_leash(ai, current_pos, 40.0)

      assert result == :ok
    end

    test "returns :ok when dead" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.set_dead()

      current_pos = {100.0, 0.0, 0.0}

      result = AI.check_leash(ai, current_pos, 40.0)

      assert result == :ok
    end

    test "returns :ok when evading" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.start_evade()

      current_pos = {100.0, 0.0, 0.0}

      result = AI.check_leash(ai, current_pos, 40.0)

      assert result == :ok
    end

    test "returns :evade at exact leash boundary + 1" do
      ai = AI.new({0.0, 0.0, 0.0}) |> AI.enter_combat(12345)

      # Creature exactly at leash boundary + 0.1
      current_pos = {40.1, 0.0, 0.0}

      result = AI.check_leash(ai, current_pos, 40.0)

      assert result == :evade
    end
  end
end
