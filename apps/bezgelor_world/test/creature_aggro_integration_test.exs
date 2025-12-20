defmodule BezgelorWorld.CreatureAggroIntegrationTest do
  @moduledoc """
  Integration tests for the complete aggro detection flow.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.CreatureManager

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

    # Clear any existing creatures with a longer timeout
    GenServer.call(pid, :clear_all_creatures, 10_000)
    :ok
  end

  describe "full aggro lifecycle" do
    test "creature aggro -> combat -> leash -> evade -> reset" do
      # 1. Spawn aggressive creature at origin
      {:ok, creature_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})

      # Verify starts idle
      {:ok, state1} = CreatureManager.get_creature_state(creature_guid)
      assert state1.ai.state == :idle
      assert state1.spawn_position == {0.0, 0.0, 0.0}

      # 2. Trigger combat manually (simulating player detection)
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(creature_guid, player_guid)
      Process.sleep(50)

      # Verify entered combat
      {:ok, state2} = CreatureManager.get_creature_state(creature_guid)
      assert state2.ai.state == :combat
      assert state2.ai.target_guid == player_guid

      # 3. Simulate creature moving far from spawn (past leash range of 40)
      # Update creature position directly
      :ok = CreatureManager.update_creature_position(creature_guid, {50.0, 0.0, 0.0})
      Process.sleep(50)

      # 4. Trigger an AI tick to check leash
      send(CreatureManager, {:tick, 1})
      Process.sleep(100)

      # Verify creature started evading
      {:ok, state3} = CreatureManager.get_creature_state(creature_guid)
      assert state3.ai.state == :evade

      # 5. Trigger more ticks to let creature move back to spawn
      # Creature moves 5 units per tick, needs ~10 ticks to cover 50 units
      for _ <- 1..15 do
        send(CreatureManager, {:tick, 1})
        Process.sleep(100)
      end

      # Verify creature reset to idle at spawn
      {:ok, state4} = CreatureManager.get_creature_state(creature_guid)
      assert state4.ai.state == :idle
      # Position should be at spawn (0,0,0)
      {x, y, z} = state4.entity.position
      assert abs(x) < 0.1
      assert abs(y) < 0.1
      assert abs(z) < 0.1
      # Verify health was restored
      assert state4.entity.health == state4.template.max_health
    end

    test "social aggro pulls nearby same-faction creatures (no cascade)" do
      # Spawn wolves all within 10m social aggro range of wolf1
      {:ok, wolf1} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})
      {:ok, wolf2} = CreatureManager.spawn_creature(2, {8.0, 0.0, 0.0})
      # ~8.5m from wolf1
      {:ok, wolf3} = CreatureManager.spawn_creature(2, {6.0, 6.0, 0.0})

      # Wolf4 is too far from wolf1 (beyond 10m social aggro range)
      {:ok, wolf4} = CreatureManager.spawn_creature(2, {100.0, 0.0, 0.0})

      # All start idle
      {:ok, s1} = CreatureManager.get_creature_state(wolf1)
      {:ok, s2} = CreatureManager.get_creature_state(wolf2)
      {:ok, s3} = CreatureManager.get_creature_state(wolf3)
      {:ok, s4} = CreatureManager.get_creature_state(wolf4)
      assert s1.ai.state == :idle
      assert s2.ai.state == :idle
      assert s3.ai.state == :idle
      assert s4.ai.state == :idle

      # Attack wolf1 -> triggers social aggro to wolf2 and wolf3 (both within 10m)
      player_guid = 0x1000000000000001
      CreatureManager.creature_enter_combat(wolf1, player_guid)
      Process.sleep(50)

      # Wolf1, wolf2, and wolf3 should all be in combat
      {:ok, s1_after} = CreatureManager.get_creature_state(wolf1)
      {:ok, s2_after} = CreatureManager.get_creature_state(wolf2)
      {:ok, s3_after} = CreatureManager.get_creature_state(wolf3)
      assert s1_after.ai.state == :combat
      assert s2_after.ai.state == :combat
      assert s3_after.ai.state == :combat

      # Wolf4 should remain idle (too far)
      {:ok, s4_after} = CreatureManager.get_creature_state(wolf4)
      assert s4_after.ai.state == :idle

      # All combat creatures should target the same player
      assert s1_after.ai.target_guid == player_guid
      assert s2_after.ai.target_guid == player_guid
      assert s3_after.ai.target_guid == player_guid
    end

    test "faction filtering - exile creature doesn't aggro exile players" do
      # Spawn a creature that we'll pretend is exile faction
      # (template 4 = Village Guard with :friendly faction)
      {:ok, guard_guid} = CreatureManager.spawn_creature(4, {0.0, 0.0, 0.0})

      # Simulate nearby exile player
      exile_player = %{
        guid: 0x1000000000000001,
        position: {5.0, 0.0, 0.0},
        faction: :exile
      }

      # Try to trigger aggro - should fail due to faction
      CreatureManager.check_aggro_for_creature(guard_guid, [exile_player])
      Process.sleep(50)

      # Guard should remain idle (friendly faction)
      {:ok, state} = CreatureManager.get_creature_state(guard_guid)
      assert state.ai.state == :idle
    end
  end
end
