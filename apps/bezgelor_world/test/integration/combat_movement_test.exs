defmodule BezgelorWorld.Integration.CombatMovementTest do
  @moduledoc """
  Integration tests for the full combat movement flow.

  Tests the complete cycle of:
  1. Creature spawns idle
  2. Creature enters combat with distant target
  3. Creature chases toward target
  4. Chase completes, creature attacks
  5. Ranged creatures maintain optimal distance
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.CreatureManager
  alias BezgelorCore.{AI, CreatureTemplate}

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

    Process.sleep(100)
    :ok
  end

  describe "full melee combat movement flow" do
    test "melee creature chases, catches up, and attacks" do
      # 1. Spawn creature at origin
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Verify initial state
      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert state1.ai.state == :idle
      assert state1.entity.position == {0.0, 0.0, 0.0}

      # 2. Enter combat with target far away
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      Process.sleep(50)

      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)
      assert state2.ai.state == :combat
      assert state2.ai.target_guid == player_guid

      # 3. Set target position far away and trigger chase
      CreatureManager.set_target_position(creature_guid, {20.0, 0.0, 0.0})
      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      # Verify chase started
      {:ok, state3} = CreatureManager.get_creature_state(creature_guid)
      assert AI.chasing?(state3.ai) == true
      assert state3.ai.chase_path != nil
      assert length(state3.ai.chase_path) > 1

      # Verify path ends near attack range (5 units from target at 20)
      {end_x, _, _} = List.last(state3.ai.chase_path)
      assert_in_delta end_x, 15.0, 1.0

      # 4. Move target closer (simulate chase complete + target moved in)
      # Wait for chase to complete
      Process.sleep(state3.ai.chase_duration + 100)

      # Now target is in range
      CreatureManager.set_target_position(creature_guid, {state3.entity.position |> elem(0) |> Kernel.+(3.0), 0.0, 0.0})
      send(CreatureManager, {:tick, 2})
      Process.sleep(100)

      # 5. Verify attack occurred
      {:ok, state4} = CreatureManager.get_creature_state(creature_guid)
      assert state4.ai.last_attack_time != nil
      # Chase should be complete
      assert AI.chasing?(state4.ai) == false
    end

    test "melee creature position updates during chase" do
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Enter combat and start chase
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      CreatureManager.set_target_position(creature_guid, {30.0, 0.0, 0.0})
      Process.sleep(50)

      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      {:ok, state} = CreatureManager.get_creature_state(creature_guid)

      # Entity position should be updated to end of chase path
      {entity_x, _, _} = state.entity.position
      assert entity_x > 0.0  # Moved from origin
    end
  end

  describe "full ranged combat movement flow" do
    test "ranged creature maintains optimal distance" do
      # Spawn ranged creature (Goblin Archer, id=6, attack_range=25)
      {:ok, creature_guid} = CreatureManager.spawn_creature(6, {0.0, 0.0, 0.0})

      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert state1.ai.state == :idle

      # Get attack range for this creature
      template = CreatureTemplate.get(6)
      attack_range = CreatureTemplate.attack_range(template)
      assert attack_range == 25.0
      assert template.is_ranged == true

      # Enter combat with target far away (60 units - beyond max range)
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      CreatureManager.set_target_position(creature_guid, {60.0, 0.0, 0.0})
      Process.sleep(50)

      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)

      # Should be chasing toward optimal range
      assert AI.chasing?(state2.ai) == true

      # Path should end at optimal distance from target
      # Optimal = (12.5 + 25) / 2 = 18.75 from target
      # So end position should be around 60 - 18.75 = 41.25
      {end_x, _, _} = List.last(state2.ai.chase_path)
      assert end_x > 35.0
      assert end_x < 50.0
    end

    test "ranged creature backs away when too close" do
      # Spawn ranged creature very close to where target will be
      {:ok, creature_guid} = CreatureManager.spawn_creature(6, {55.0, 0.0, 0.0})

      # Enter combat - target at 60, creature at 55 = 5 units (too close)
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      CreatureManager.set_target_position(creature_guid, {60.0, 0.0, 0.0})
      Process.sleep(50)

      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      {:ok, state} = CreatureManager.get_creature_state(creature_guid)

      # Should be repositioning (backing away)
      assert AI.chasing?(state.ai) == true

      # End position should be further from target (lower X since backing away)
      {end_x, _, _} = List.last(state.ai.chase_path)
      assert end_x < 55.0  # Moved away from 55
    end
  end

  describe "combat movement timing" do
    test "chase duration is based on path length and speed" do
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Enter combat and chase
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      CreatureManager.set_target_position(creature_guid, {20.0, 0.0, 0.0})
      Process.sleep(50)

      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      {:ok, state} = CreatureManager.get_creature_state(creature_guid)

      # Verify chase has reasonable duration
      # Path is ~15 units, speed is 4 units/sec = ~3750ms
      assert state.ai.chase_duration > 2000
      assert state.ai.chase_duration < 6000
    end

    test "chase completes after duration expires" do
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Start chase
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      CreatureManager.set_target_position(creature_guid, {12.0, 0.0, 0.0})  # Short chase
      Process.sleep(50)

      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert AI.chasing?(state1.ai) == true
      duration = state1.ai.chase_duration

      # Wait for chase to complete
      Process.sleep(duration + 200)

      # Chase should now be complete (time expired)
      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)
      assert AI.chasing?(state2.ai) == false
    end
  end
end
