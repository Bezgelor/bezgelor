defmodule BezgelorWorld.CreatureChaseMovementTest do
  @moduledoc """
  Tests for creature chase movement during combat.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.CreatureManager
  alias BezgelorCore.AI

  setup do
    # Start CreatureManager if not running
    pid =
      case GenServer.whereis(CreatureManager) do
        nil ->
          {:ok, pid} = start_supervised!(CreatureManager)
          pid

        existing_pid ->
          existing_pid
      end

    # Clear any existing creatures
    GenServer.call(pid, :clear_all_creatures, 10_000)
    :ok
  end

  describe "chase movement in combat" do
    test "creature starts chasing when target is out of attack range" do
      # Spawn creature at origin
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Verify starts idle
      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert state1.ai.state == :idle

      # Enter combat with target far away
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      Process.sleep(50)

      # Verify entered combat
      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)
      assert state2.ai.state == :combat

      # Simulate target position far away (beyond attack range of 5)
      # and trigger AI tick
      CreatureManager.set_target_position(creature_guid, {20.0, 0.0, 0.0})
      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      # Verify creature started chasing
      {:ok, state3} = CreatureManager.get_creature_state(creature_guid)
      assert AI.chasing?(state3.ai) == true
      assert state3.ai.chase_path != nil
    end

    test "creature attacks when target is in attack range" do
      # Spawn creature at origin
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Enter combat
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      Process.sleep(50)

      # Set target position within attack range (5 units)
      CreatureManager.set_target_position(creature_guid, {3.0, 0.0, 0.0})
      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      # Verify NOT chasing (should attack instead)
      {:ok, state} = CreatureManager.get_creature_state(creature_guid)
      assert AI.chasing?(state.ai) == false
      # Attack should have been recorded
      assert state.ai.last_attack_time != nil
    end

    test "creature waits while chase is in progress" do
      # Spawn creature at origin
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Enter combat
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      Process.sleep(50)

      # Set target far away and trigger chase
      CreatureManager.set_target_position(creature_guid, {20.0, 0.0, 0.0})
      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      # Verify chasing
      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert AI.chasing?(state1.ai) == true
      chase_start_time = state1.ai.chase_start_time

      # Trigger another tick - should wait (not start new chase)
      send(CreatureManager, {:tick, 2})
      Process.sleep(100)

      # Chase should still be active with same start time
      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)
      assert state2.ai.chase_start_time == chase_start_time
    end
  end
end
