defmodule BezgelorWorld.CreatureManagerTest do
  @moduledoc """
  Tests for creature management functionality in World.Instance.

  These tests verify the per-zone creature management that was migrated
  from the global CreatureManager singleton to per-World.Instance.
  """
  use ExUnit.Case, async: false

  alias BezgelorWorld.World.{Instance, InstanceSupervisor}
  alias BezgelorCore.{AI, CreatureTemplate}

  # Test world key - we use a unique world_id to avoid conflicts
  @test_world_id 99999
  @test_instance_id 1
  @test_world_key {@test_world_id, @test_instance_id}

  setup do
    # Start a test world instance
    world_data = %{id: @test_world_id, name: "Test Zone", is_test: true}

    case InstanceSupervisor.start_instance(@test_world_id, @test_instance_id, world_data) do
      {:ok, pid} ->
        on_exit(fn ->
          # Clean up the test instance
          InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id)
        end)

        {:ok, %{instance_pid: pid, world_key: @test_world_key}}

      {:error, {:already_started, pid}} ->
        {:ok, %{instance_pid: pid, world_key: @test_world_key}}
    end
  end

  describe "spawn_creature/3" do
    test "spawns creature from template", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 1, {100.0, 200.0, 300.0})

      assert is_integer(guid)
      assert guid > 0
    end

    test "returns error for unknown template", %{world_key: world_key} do
      {:error, :template_not_found} =
        Instance.spawn_creature(world_key, 999_999, {0.0, 0.0, 0.0})
    end

    test "creature has correct initial state", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 2, {110.0, 220.0, 330.0})
      creature = Instance.get_creature(world_key, guid)

      template = CreatureTemplate.get(2)

      assert creature.entity.name == template.name
      assert creature.entity.health == template.max_health
      assert creature.entity.position == {110.0, 220.0, 330.0}
      assert creature.spawn_position == {110.0, 220.0, 330.0}
      assert creature.ai.state == :idle
    end
  end

  describe "get_creature/2" do
    test "returns creature by GUID", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 1, {200.0, 200.0, 200.0})
      creature = Instance.get_creature(world_key, guid)

      assert creature != nil
      assert creature.entity.guid == guid
    end

    test "returns nil for unknown GUID", %{world_key: world_key} do
      assert nil == Instance.get_creature(world_key, 999_999_999)
    end
  end

  describe "list_creatures/1" do
    test "returns list of spawned creatures", %{world_key: world_key} do
      initial_count = Instance.creature_count(world_key)
      {:ok, _} = Instance.spawn_creature(world_key, 1, {300.0, 300.0, 300.0})
      {:ok, _} = Instance.spawn_creature(world_key, 2, {310.0, 300.0, 300.0})

      creatures = Instance.list_creatures(world_key)

      assert length(creatures) >= initial_count + 2
    end
  end

  describe "get_creatures_in_range/3" do
    test "returns creatures within range", %{world_key: world_key} do
      {:ok, _} = Instance.spawn_creature(world_key, 1, {1000.0, 1000.0, 1000.0})
      {:ok, _} = Instance.spawn_creature(world_key, 2, {1005.0, 1000.0, 1000.0})
      {:ok, _} = Instance.spawn_creature(world_key, 3, {1050.0, 1000.0, 1000.0})

      creatures = Instance.get_creatures_in_range(world_key, {1000.0, 1000.0, 1000.0}, 10.0)

      assert length(creatures) == 2
    end

    test "excludes dead creatures", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 1, {2000.0, 2000.0, 2000.0})

      # Kill the creature
      {:ok, :killed, _} = Instance.damage_creature(world_key, guid, 12345, 1000)

      creatures = Instance.get_creatures_in_range(world_key, {2000.0, 2000.0, 2000.0}, 10.0)

      # Dead creature should not be included
      refute Enum.any?(creatures, fn c -> c.entity.guid == guid end)
    end
  end

  describe "damage_creature/4" do
    test "reduces creature health", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 2, {3000.0, 3000.0, 3000.0})

      {:ok, :damaged, info} = Instance.damage_creature(world_key, guid, 12345, 50)

      template = CreatureTemplate.get(2)
      assert info.remaining_health == template.max_health - 50
    end

    test "creature enters combat when damaged", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 2, {3100.0, 3000.0, 3000.0})

      {:ok, :damaged, _} = Instance.damage_creature(world_key, guid, 12345, 10)

      creature = Instance.get_creature(world_key, guid)
      assert AI.in_combat?(creature.ai)
      assert creature.ai.target_guid == 12345
    end

    test "kills creature when damage exceeds health", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 1, {3200.0, 3000.0, 3000.0})

      {:ok, :killed, info} = Instance.damage_creature(world_key, guid, 12345, 1000)

      assert info.xp_reward > 0
      assert info.killer_guid == 12345

      creature = Instance.get_creature(world_key, guid)
      assert AI.dead?(creature.ai)
    end

    test "returns error for unknown creature", %{world_key: world_key} do
      {:error, :creature_not_found} =
        Instance.damage_creature(world_key, 999_999_999, 12345, 50)
    end

    test "returns error for dead creature", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 1, {3300.0, 3000.0, 3000.0})

      # Kill the creature
      {:ok, :killed, _} = Instance.damage_creature(world_key, guid, 12345, 1000)

      # Try to damage again
      {:error, :creature_dead} = Instance.damage_creature(world_key, guid, 12345, 50)
    end

    test "generates loot on kill", %{world_key: world_key} do
      # Cave Spider (id 2) has loot table
      {:ok, guid} = Instance.spawn_creature(world_key, 2, {3400.0, 3000.0, 3000.0})

      {:ok, :killed, info} = Instance.damage_creature(world_key, guid, 12345, 1000)

      # Loot drops are random but should include gold (100% chance)
      assert info.gold >= 0
      assert is_list(info.items)
      assert is_list(info.loot_drops)
    end
  end

  describe "creature_enter_combat/3" do
    test "puts creature in combat", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 2, {4000.0, 4000.0, 4000.0})

      :ok = Instance.creature_enter_combat(world_key, guid, 12345)

      creature = Instance.get_creature(world_key, guid)
      assert AI.in_combat?(creature.ai)
    end
  end

  describe "creature_targetable?/2" do
    test "returns true for alive creatures", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 1, {5000.0, 5000.0, 5000.0})

      assert Instance.creature_targetable?(world_key, guid)
    end

    test "returns false for dead creatures", %{world_key: world_key} do
      {:ok, guid} = Instance.spawn_creature(world_key, 1, {5100.0, 5000.0, 5000.0})

      # Kill the creature
      {:ok, :killed, _} = Instance.damage_creature(world_key, guid, 12345, 1000)

      refute Instance.creature_targetable?(world_key, guid)
    end

    test "returns false for unknown creatures", %{world_key: world_key} do
      refute Instance.creature_targetable?(world_key, 999_999_999)
    end
  end

  describe "creature_count/1" do
    test "returns number of creatures", %{world_key: world_key} do
      initial_count = Instance.creature_count(world_key)

      {:ok, _} = Instance.spawn_creature(world_key, 1, {6000.0, 6000.0, 6000.0})
      assert Instance.creature_count(world_key) == initial_count + 1

      {:ok, _} = Instance.spawn_creature(world_key, 2, {6100.0, 6000.0, 6000.0})
      assert Instance.creature_count(world_key) == initial_count + 2
    end
  end

  describe "deprecated CreatureManager facade" do
    alias BezgelorWorld.CreatureManager

    test "facade functions are deprecated but still work with existing instances", %{
      world_key: world_key
    } do
      # Spawn via Instance
      {:ok, guid} = Instance.spawn_creature(world_key, 1, {7000.0, 7000.0, 7000.0})

      # Query via facade - should find the creature
      creature = CreatureManager.get_creature(guid)
      assert creature != nil
      assert creature.entity.guid == guid

      # Damage via facade
      {:ok, :damaged, _} = CreatureManager.damage_creature(guid, 12345, 10)

      # Verify damage was applied
      creature = Instance.get_creature(world_key, guid)
      template = CreatureTemplate.get(1)
      assert creature.entity.health == template.max_health - 10
    end

    test "facade returns errors for non-existent creatures" do
      assert nil == CreatureManager.get_creature(888_888_888)
      assert {:error, :creature_not_found} == CreatureManager.damage_creature(888_888_888, 1, 10)
    end
  end
end
