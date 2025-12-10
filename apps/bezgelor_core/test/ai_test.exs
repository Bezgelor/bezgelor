defmodule BezgelorCore.AITest do
  use ExUnit.Case, async: true

  alias BezgelorCore.AI

  defp make_ai(attrs \\ %{}) do
    spawn_pos = Map.get(attrs, :spawn_position, {0.0, 0.0, 0.0})

    %AI{
      state: Map.get(attrs, :state, :idle),
      target_guid: Map.get(attrs, :target_guid, nil),
      spawn_position: spawn_pos,
      threat_table: Map.get(attrs, :threat_table, %{})
    }
  end

  describe "new/1" do
    test "creates idle AI with spawn position" do
      ai = AI.new({10.0, 20.0, 30.0})

      assert ai.state == :idle
      assert ai.spawn_position == {10.0, 20.0, 30.0}
      assert ai.target_guid == nil
      assert ai.threat_table == %{}
    end
  end

  describe "get_state/1" do
    test "returns current state" do
      ai = make_ai(%{state: :combat})
      assert AI.get_state(ai) == :combat
    end
  end

  describe "in_combat?/1" do
    test "returns true when in combat" do
      ai = make_ai(%{state: :combat})
      assert AI.in_combat?(ai)
    end

    test "returns false when not in combat" do
      assert not AI.in_combat?(make_ai(%{state: :idle}))
      assert not AI.in_combat?(make_ai(%{state: :evade}))
      assert not AI.in_combat?(make_ai(%{state: :dead}))
    end
  end

  describe "dead?/1" do
    test "returns true when dead" do
      ai = make_ai(%{state: :dead})
      assert AI.dead?(ai)
    end

    test "returns false when alive" do
      refute AI.dead?(make_ai(%{state: :idle}))
      refute AI.dead?(make_ai(%{state: :combat}))
    end
  end

  describe "targetable?/1" do
    test "returns false when dead" do
      ai = make_ai(%{state: :dead})
      refute AI.targetable?(ai)
    end

    test "returns true when alive" do
      assert AI.targetable?(make_ai(%{state: :idle}))
      assert AI.targetable?(make_ai(%{state: :combat}))
      assert AI.targetable?(make_ai(%{state: :evade}))
    end
  end

  describe "enter_combat/2" do
    test "transitions to combat state" do
      ai = make_ai()
      ai = AI.enter_combat(ai, 12345)

      assert ai.state == :combat
      assert ai.target_guid == 12345
      assert ai.combat_start_time != nil
    end

    test "adds target to threat table" do
      ai = make_ai()
      ai = AI.enter_combat(ai, 12345)

      assert Map.has_key?(ai.threat_table, 12345)
      assert ai.threat_table[12345] == 100
    end

    test "does nothing when dead" do
      ai = make_ai(%{state: :dead})
      ai = AI.enter_combat(ai, 12345)

      assert ai.state == :dead
      assert ai.target_guid == nil
    end
  end

  describe "exit_combat/1" do
    test "returns to idle state" do
      ai = make_ai(%{state: :combat, target_guid: 12345, threat_table: %{12345 => 100}})
      ai = AI.exit_combat(ai)

      assert ai.state == :idle
      assert ai.target_guid == nil
      assert ai.threat_table == %{}
    end
  end

  describe "start_evade/1" do
    test "transitions to evade state" do
      ai = make_ai(%{state: :combat, target_guid: 12345})
      ai = AI.start_evade(ai)

      assert ai.state == :evade
      assert ai.target_guid == nil
    end
  end

  describe "complete_evade/1" do
    test "returns to idle and clears threat" do
      ai = make_ai(%{state: :evade, threat_table: %{12345 => 100}})
      ai = AI.complete_evade(ai)

      assert ai.state == :idle
      assert ai.threat_table == %{}
    end
  end

  describe "set_dead/1" do
    test "transitions to dead state" do
      ai = make_ai(%{state: :combat, target_guid: 12345, threat_table: %{12345 => 100}})
      ai = AI.set_dead(ai)

      assert ai.state == :dead
      assert ai.target_guid == nil
      assert ai.threat_table == %{}
    end
  end

  describe "respawn/1" do
    test "returns to idle from dead" do
      ai = make_ai(%{state: :dead})
      ai = AI.respawn(ai)

      assert ai.state == :idle
    end
  end

  describe "threat management" do
    test "add_threat/3 adds threat for target" do
      ai = make_ai()
      ai = AI.add_threat(ai, 12345, 50)

      assert ai.threat_table[12345] == 50
    end

    test "add_threat/3 stacks with existing threat" do
      ai = make_ai(%{threat_table: %{12345 => 50}})
      ai = AI.add_threat(ai, 12345, 30)

      assert ai.threat_table[12345] == 80
    end

    test "highest_threat_target/1 returns target with most threat" do
      ai = make_ai(%{threat_table: %{1 => 50, 2 => 100, 3 => 75}})

      assert AI.highest_threat_target(ai) == 2
    end

    test "highest_threat_target/1 returns nil when no threats" do
      ai = make_ai()

      assert AI.highest_threat_target(ai) == nil
    end

    test "remove_threat_target/2 removes target" do
      ai = make_ai(%{threat_table: %{1 => 50, 2 => 100}, target_guid: 1})
      ai = AI.remove_threat_target(ai, 1)

      refute Map.has_key?(ai.threat_table, 1)
    end

    test "remove_threat_target/2 switches to highest threat if current removed" do
      ai = make_ai(%{state: :combat, threat_table: %{1 => 50, 2 => 100}, target_guid: 1})
      ai = AI.remove_threat_target(ai, 1)

      assert ai.target_guid == 2
    end

    test "remove_threat_target/2 exits combat when no targets left" do
      ai = make_ai(%{state: :combat, threat_table: %{1 => 50}, target_guid: 1})
      ai = AI.remove_threat_target(ai, 1)

      assert ai.state == :idle
      assert ai.target_guid == nil
    end
  end

  describe "attack timing" do
    test "can_attack?/2 respects attack speed" do
      ai = make_ai()
      # Should be able to attack immediately (last_attack_time is 0)
      assert AI.can_attack?(ai, 2000)
    end

    test "record_attack/1 updates last attack time" do
      ai = make_ai()
      ai = AI.record_attack(ai)

      # Should not be able to attack again immediately
      refute AI.can_attack?(ai, 2000)
    end
  end

  describe "distance/2" do
    test "calculates 3D distance" do
      assert AI.distance({0.0, 0.0, 0.0}, {3.0, 4.0, 0.0}) == 5.0
      assert AI.distance({0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}) == 0.0
    end
  end

  describe "within_leash?/3" do
    test "returns true when within range" do
      ai = make_ai(%{spawn_position: {0.0, 0.0, 0.0}})
      assert AI.within_leash?(ai, {10.0, 0.0, 0.0}, 40.0)
    end

    test "returns false when outside range" do
      ai = make_ai(%{spawn_position: {0.0, 0.0, 0.0}})
      refute AI.within_leash?(ai, {50.0, 0.0, 0.0}, 40.0)
    end
  end

  describe "in_aggro_range?/3" do
    test "returns true when within aggro range" do
      assert AI.in_aggro_range?({0.0, 0.0, 0.0}, {5.0, 0.0, 0.0}, 10.0)
    end

    test "returns false when outside aggro range" do
      refute AI.in_aggro_range?({0.0, 0.0, 0.0}, {15.0, 0.0, 0.0}, 10.0)
    end
  end

  describe "tick/2" do
    test "returns :none when dead" do
      ai = make_ai(%{state: :dead})
      assert :none == AI.tick(ai, %{})
    end

    test "returns :none when idle" do
      ai = make_ai(%{state: :idle})
      assert :none == AI.tick(ai, %{})
    end

    test "returns move_to spawn when evading" do
      ai = make_ai(%{state: :evade, spawn_position: {10.0, 20.0, 30.0}})
      assert {:move_to, {10.0, 20.0, 30.0}} == AI.tick(ai, %{})
    end

    test "returns :none in combat with no target" do
      ai = make_ai(%{state: :combat, target_guid: nil})
      assert :none == AI.tick(ai, %{})
    end

    test "returns attack when can attack target" do
      ai = make_ai(%{state: :combat, target_guid: 12345})
      assert {:attack, 12345} == AI.tick(ai, %{attack_speed: 2000})
    end

    test "returns :none in combat when attack on cooldown" do
      ai =
        make_ai(%{state: :combat, target_guid: 12345})
        |> AI.record_attack()

      assert :none == AI.tick(ai, %{attack_speed: 2000})
    end
  end
end
