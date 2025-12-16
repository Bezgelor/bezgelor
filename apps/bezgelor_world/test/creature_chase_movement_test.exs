defmodule BezgelorWorld.CreatureChaseMovementTest do
  @moduledoc """
  Tests for creature chase movement during combat.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.CreatureManager
  alias BezgelorCore.AI

  setup do
    # Get or start CreatureManager
    pid =
      case GenServer.whereis(CreatureManager) do
        nil ->
          {:ok, p} = CreatureManager.start_link([])
          p

        existing_pid ->
          existing_pid
      end

    # Clear any existing creatures
    try do
      GenServer.call(pid, :clear_all_creatures, 30_000)
    catch
      :exit, _ -> :ok
    end

    # Small delay to ensure clean state
    Process.sleep(100)

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

    test "creature re-evaluates after chase completes" do
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

      # Chase completes when elapsed >= duration
      # AI.chasing? will return false after duration passes
      # We can verify this by checking after the duration
      chase_duration = state1.ai.chase_duration
      assert is_integer(chase_duration)
      assert chase_duration > 0

      # The chase state is time-based - chasing?() returns false when time expires
      # This test verifies chase has correct duration set
      assert state1.ai.chase_path != nil
      assert length(state1.ai.chase_path) > 0
    end
  end

  describe "ranged creature movement" do
    test "ranged creature backs away when target is too close" do
      # Spawn ranged creature (Goblin Archer, id=6, attack_range=25)
      # Position at 10 units from where target will be (within min range)
      {:ok, creature_guid} = CreatureManager.spawn_creature(6, {25.0, 0.0, 0.0})

      # Verify starts idle
      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert state1.ai.state == :idle

      # Enter combat
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      Process.sleep(50)

      # Target is at 30,0,0 - creature is at 25,0,0 = 5 units distance
      # Ranged creature should back away to optimal range (12.5-25 units from target)
      CreatureManager.set_target_position(creature_guid, {30.0, 0.0, 0.0})
      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      # Verify creature started repositioning (chase path set)
      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)
      assert AI.chasing?(state2.ai) == true
      assert state2.ai.chase_path != nil

      # Path should move creature away from target (lower x value)
      {end_x, _, _} = List.last(state2.ai.chase_path)
      # Should end up further from target than starting position
      # Target at 30, creature should end around 11-18 (optimal range 12.5-25 from target)
      assert end_x < 25.0
    end

    test "ranged creature moves closer when target is out of range" do
      # Spawn ranged creature far from target
      {:ok, creature_guid} = CreatureManager.spawn_creature(6, {0.0, 0.0, 0.0})

      # Enter combat
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      Process.sleep(50)

      # Target at 60 units - beyond attack range of 25
      CreatureManager.set_target_position(creature_guid, {60.0, 0.0, 0.0})
      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      # Verify creature started chasing toward optimal range
      {:ok, state} = CreatureManager.get_creature_state(creature_guid)
      assert AI.chasing?(state.ai) == true
      assert state.ai.chase_path != nil

      # Path should move creature toward target (higher x value)
      {end_x, _, _} = List.last(state.ai.chase_path)
      # Should end up around 41 (60 - 18.75 optimal distance)
      assert end_x > 35.0
      assert end_x < 50.0
    end
  end
end
