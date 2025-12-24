defmodule BezgelorWorld.CreatureSocialAggroTest do
  @moduledoc """
  Tests for creature social aggro behavior - nearby same-faction creatures
  should join combat when one is attacked.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.World.{Instance, InstanceSupervisor}

  # Test world key
  @test_world_id 99998
  @test_instance_id 1
  @test_world_key {@test_world_id, @test_instance_id}

  setup do
    # Start a test world instance
    world_data = %{id: @test_world_id, name: "Social Aggro Test Zone", is_test: true}

    case InstanceSupervisor.start_instance(@test_world_id, @test_instance_id, world_data) do
      {:ok, pid} ->
        on_exit(fn ->
          InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id)
        end)

        {:ok, %{instance_pid: pid, world_key: @test_world_key}}

      {:error, {:already_started, pid}} ->
        {:ok, %{instance_pid: pid, world_key: @test_world_key}}
    end
  end

  describe "social aggro" do
    test "nearby same-faction creatures join combat", %{world_key: world_key} do
      # Spawn two wolves near each other (same faction: hostile)
      {:ok, wolf1_guid} = Instance.spawn_creature(world_key, 2, {0.0, 0.0, 0.0})
      {:ok, wolf2_guid} = Instance.spawn_creature(world_key, 2, {5.0, 0.0, 0.0})

      # Verify both start idle
      wolf1_initial = Instance.get_creature(world_key, wolf1_guid)
      wolf2_initial = Instance.get_creature(world_key, wolf2_guid)
      assert wolf1_initial.ai.state == :idle
      assert wolf2_initial.ai.state == :idle

      # Trigger combat for wolf1
      Instance.creature_enter_combat(world_key, wolf1_guid, 0x1000000000000001)

      # Allow social aggro to propagate
      Process.sleep(50)

      # Wolf1 should be in combat
      wolf1_state = Instance.get_creature(world_key, wolf1_guid)
      assert wolf1_state.ai.state == :combat

      # Wolf2 should also be in combat (social aggro)
      wolf2_state = Instance.get_creature(world_key, wolf2_guid)
      assert wolf2_state.ai.state == :combat
      assert wolf2_state.ai.target_guid == 0x1000000000000001
    end

    test "distant creatures don't join combat", %{world_key: world_key} do
      # Spawn two wolves far apart (beyond 10m social aggro range)
      {:ok, wolf1_guid} = Instance.spawn_creature(world_key, 2, {0.0, 0.0, 0.0})
      {:ok, wolf2_guid} = Instance.spawn_creature(world_key, 2, {50.0, 0.0, 0.0})

      # Trigger combat for wolf1
      Instance.creature_enter_combat(world_key, wolf1_guid, 0x1000000000000001)
      Process.sleep(50)

      # Wolf1 should be in combat
      wolf1_state = Instance.get_creature(world_key, wolf1_guid)
      assert wolf1_state.ai.state == :combat

      # Wolf2 should stay idle (too far for social aggro)
      wolf2_state = Instance.get_creature(world_key, wolf2_guid)
      assert wolf2_state.ai.state == :idle
    end

    test "creatures already in combat don't switch targets from social aggro", %{
      world_key: world_key
    } do
      # Spawn two wolves near each other
      {:ok, wolf1_guid} = Instance.spawn_creature(world_key, 2, {0.0, 0.0, 0.0})
      {:ok, wolf2_guid} = Instance.spawn_creature(world_key, 2, {5.0, 0.0, 0.0})

      # Put wolf2 in combat with a different target first
      Instance.creature_enter_combat(world_key, wolf2_guid, 0x1000000000000002)
      Process.sleep(50)

      wolf2_before = Instance.get_creature(world_key, wolf2_guid)
      assert wolf2_before.ai.state == :combat
      assert wolf2_before.ai.target_guid == 0x1000000000000002

      # Now trigger combat for wolf1 (which should trigger social aggro)
      Instance.creature_enter_combat(world_key, wolf1_guid, 0x1000000000000001)
      Process.sleep(50)

      # Wolf2 should still have its original target
      wolf2_after = Instance.get_creature(world_key, wolf2_guid)
      assert wolf2_after.ai.target_guid == 0x1000000000000002
    end
  end
end
