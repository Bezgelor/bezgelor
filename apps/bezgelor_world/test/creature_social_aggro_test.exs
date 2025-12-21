defmodule BezgelorWorld.CreatureSocialAggroTest do
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

  describe "social aggro" do
    test "nearby same-faction creatures join combat" do
      # Spawn two wolves near each other (same faction: hostile)
      {:ok, wolf1_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})
      {:ok, wolf2_guid} = CreatureManager.spawn_creature(2, {5.0, 0.0, 0.0})

      # Verify both start idle
      {:ok, wolf1_initial} = CreatureManager.get_creature_state(wolf1_guid)
      {:ok, wolf2_initial} = CreatureManager.get_creature_state(wolf2_guid)
      assert wolf1_initial.ai.state == :idle
      assert wolf2_initial.ai.state == :idle

      # Trigger combat for wolf1
      CreatureManager.creature_enter_combat(wolf1_guid, 0x1000000000000001)

      # Allow social aggro to propagate
      Process.sleep(50)

      # Wolf1 should be in combat
      {:ok, wolf1_state} = CreatureManager.get_creature_state(wolf1_guid)
      assert wolf1_state.ai.state == :combat

      # Wolf2 should also be in combat (social aggro)
      {:ok, wolf2_state} = CreatureManager.get_creature_state(wolf2_guid)
      assert wolf2_state.ai.state == :combat
      assert wolf2_state.ai.target_guid == 0x1000000000000001
    end

    test "distant creatures don't join combat" do
      # Spawn two wolves far apart (beyond 10m social aggro range)
      {:ok, wolf1_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})
      {:ok, wolf2_guid} = CreatureManager.spawn_creature(2, {50.0, 0.0, 0.0})

      # Trigger combat for wolf1
      CreatureManager.creature_enter_combat(wolf1_guid, 0x1000000000000001)
      Process.sleep(50)

      # Wolf1 should be in combat
      {:ok, wolf1_state} = CreatureManager.get_creature_state(wolf1_guid)
      assert wolf1_state.ai.state == :combat

      # Wolf2 should stay idle (too far for social aggro)
      {:ok, wolf2_state} = CreatureManager.get_creature_state(wolf2_guid)
      assert wolf2_state.ai.state == :idle
    end

    test "creatures already in combat don't switch targets from social aggro" do
      # Spawn two wolves near each other
      {:ok, wolf1_guid} = CreatureManager.spawn_creature(2, {0.0, 0.0, 0.0})
      {:ok, wolf2_guid} = CreatureManager.spawn_creature(2, {5.0, 0.0, 0.0})

      # Put wolf2 in combat with a different target first
      CreatureManager.creature_enter_combat(wolf2_guid, 0x1000000000000002)
      Process.sleep(50)

      {:ok, wolf2_before} = CreatureManager.get_creature_state(wolf2_guid)
      assert wolf2_before.ai.state == :combat
      assert wolf2_before.ai.target_guid == 0x1000000000000002

      # Now trigger combat for wolf1 (which should trigger social aggro)
      CreatureManager.creature_enter_combat(wolf1_guid, 0x1000000000000001)
      Process.sleep(50)

      # Wolf2 should still have its original target
      {:ok, wolf2_after} = CreatureManager.get_creature_state(wolf2_guid)
      assert wolf2_after.ai.target_guid == 0x1000000000000002
    end
  end
end
