defmodule BezgelorWorld.World.InstanceTest do
  @moduledoc """
  Tests for World.Instance GenServer functionality.

  Tests lazy zone loading, harvest node management, and instance lifecycle.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias BezgelorWorld.World.{Instance, InstanceSupervisor}
  alias BezgelorCore.Entity

  # Test world key - unique to avoid conflicts
  @test_world_id 88888
  @test_instance_id 1
  @test_world_key {@test_world_id, @test_instance_id}

  # =====================================================================
  # Lazy Zone Loading Tests
  # =====================================================================

  describe "lazy zone loading" do
    setup do
      # Ensure clean state
      InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id)
      :ok
    end

    test "starts with spawns deferred when lazy_loading: true" do
      world_data = %{id: @test_world_id, name: "Lazy Test Zone"}

      {:ok, pid} =
        InstanceSupervisor.start_instance(
          @test_world_id,
          @test_instance_id,
          world_data,
          lazy_loading: true
        )

      on_exit(fn -> InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id) end)

      # Get state directly to verify spawns not loaded
      state = :sys.get_state(pid)
      assert state.lazy_loading == true
      assert state.spawns_loaded == false
    end

    test "loads spawns when first player enters with lazy loading" do
      world_data = %{id: @test_world_id, name: "Lazy Test Zone"}

      {:ok, pid} =
        InstanceSupervisor.start_instance(
          @test_world_id,
          @test_instance_id,
          world_data,
          lazy_loading: true
        )

      on_exit(fn -> InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id) end)

      # Verify spawns not loaded yet
      state_before = :sys.get_state(pid)
      assert state_before.spawns_loaded == false

      # Add a player entity
      player = %Entity{
        guid: 1_000_001,
        type: :player,
        name: "TestPlayer",
        position: {100.0, 100.0, 100.0},
        health: 1000,
        max_health: 1000
      }

      Instance.add_entity(@test_world_key, player)
      # Give time for async processing
      Process.sleep(100)

      # Verify spawns now loaded
      state_after = :sys.get_state(pid)
      assert state_after.spawns_loaded == true
    end

    test "starts idle timeout when last player leaves" do
      world_data = %{id: @test_world_id, name: "Lazy Test Zone"}

      {:ok, pid} =
        InstanceSupervisor.start_instance(
          @test_world_id,
          @test_instance_id,
          world_data,
          lazy_loading: true
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id)
        end
      end)

      # Add then remove a player
      player = %Entity{
        guid: 1_000_002,
        type: :player,
        name: "TestPlayer",
        position: {100.0, 100.0, 100.0},
        health: 1000,
        max_health: 1000
      }

      Instance.add_entity(@test_world_key, player)
      Process.sleep(50)

      Instance.remove_entity(@test_world_key, player.guid)
      Process.sleep(50)

      # Verify idle timeout started
      state = :sys.get_state(pid)
      assert state.idle_timeout_ref != nil
      assert state.last_player_left_at != nil
    end

    test "cancels idle timeout when player enters" do
      world_data = %{id: @test_world_id, name: "Lazy Test Zone"}

      {:ok, pid} =
        InstanceSupervisor.start_instance(
          @test_world_id,
          @test_instance_id,
          world_data,
          lazy_loading: true
        )

      on_exit(fn -> InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id) end)

      # Add and remove a player to start idle timeout
      player1 = %Entity{
        guid: 1_000_003,
        type: :player,
        name: "TestPlayer1",
        position: {100.0, 100.0, 100.0},
        health: 1000,
        max_health: 1000
      }

      Instance.add_entity(@test_world_key, player1)
      Process.sleep(50)
      Instance.remove_entity(@test_world_key, player1.guid)
      Process.sleep(50)

      # Verify idle timeout is set
      state_idle = :sys.get_state(pid)
      assert state_idle.idle_timeout_ref != nil

      # Add another player
      player2 = %Entity{
        guid: 1_000_004,
        type: :player,
        name: "TestPlayer2",
        position: {100.0, 100.0, 100.0},
        health: 1000,
        max_health: 1000
      }

      Instance.add_entity(@test_world_key, player2)
      Process.sleep(50)

      # Verify idle timeout cancelled
      state_active = :sys.get_state(pid)
      assert state_active.idle_timeout_ref == nil
      assert state_active.last_player_left_at == nil
    end

    test "loads spawns immediately when lazy_loading: false" do
      world_data = %{id: @test_world_id, name: "Eager Test Zone"}

      {:ok, pid} =
        InstanceSupervisor.start_instance(
          @test_world_id,
          @test_instance_id,
          world_data,
          lazy_loading: false
        )

      on_exit(fn -> InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id) end)

      # Give time for async spawn loading
      Process.sleep(100)

      state = :sys.get_state(pid)
      assert state.spawns_loaded == true
    end
  end

  # =====================================================================
  # Harvest Node Tests
  # =====================================================================

  describe "harvest node management" do
    setup do
      world_data = %{id: @test_world_id, name: "Harvest Test Zone"}

      case InstanceSupervisor.start_instance(@test_world_id, @test_instance_id, world_data) do
        {:ok, pid} ->
          on_exit(fn -> InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id) end)
          Process.sleep(100)  # Wait for spawn loading
          {:ok, %{instance_pid: pid, world_key: @test_world_key}}

        {:error, {:already_started, pid}} ->
          {:ok, %{instance_pid: pid, world_key: @test_world_key}}
      end
    end

    test "list_harvest_nodes/1 returns list", %{world_key: world_key} do
      nodes = Instance.list_harvest_nodes(world_key)
      assert is_list(nodes)
    end

    test "harvest_node_count/1 returns count", %{world_key: world_key} do
      count = Instance.harvest_node_count(world_key)
      assert is_integer(count)
      assert count >= 0
    end

    test "get_harvest_node/2 returns nil for unknown GUID", %{world_key: world_key} do
      assert nil == Instance.get_harvest_node(world_key, 999_999_999)
    end

    test "harvest_node_available?/2 returns false for unknown GUID", %{world_key: world_key} do
      refute Instance.harvest_node_available?(world_key, 999_999_999)
    end

    test "gather_harvest_node/3 returns error for unknown GUID", %{world_key: world_key} do
      {:error, :not_found} =
        Instance.gather_harvest_node(world_key, 999_999_999, 12345)
    end
  end

  # =====================================================================
  # Entity Management Tests
  # =====================================================================

  describe "entity management" do
    setup do
      world_data = %{id: @test_world_id, name: "Entity Test Zone"}

      case InstanceSupervisor.start_instance(@test_world_id, @test_instance_id, world_data) do
        {:ok, pid} ->
          on_exit(fn -> InstanceSupervisor.stop_instance(@test_world_id, @test_instance_id) end)
          {:ok, %{instance_pid: pid, world_key: @test_world_key}}

        {:error, {:already_started, pid}} ->
          {:ok, %{instance_pid: pid, world_key: @test_world_key}}
      end
    end

    test "add_entity/2 and get_entity/2 round-trip", %{world_key: world_key} do
      entity = %Entity{
        guid: 2_000_001,
        type: :npc,
        name: "Test NPC",
        position: {500.0, 500.0, 500.0},
        health: 100,
        max_health: 100
      }

      :ok = Instance.add_entity(world_key, entity)
      {:ok, retrieved} = Instance.get_entity(world_key, entity.guid)

      assert retrieved.guid == entity.guid
      assert retrieved.name == entity.name
    end

    test "remove_entity/2 removes entity", %{world_key: world_key} do
      entity = %Entity{
        guid: 2_000_002,
        type: :npc,
        name: "Test NPC",
        position: {600.0, 600.0, 600.0},
        health: 100,
        max_health: 100
      }

      Instance.add_entity(world_key, entity)
      {:ok, _} = Instance.get_entity(world_key, entity.guid)

      Instance.remove_entity(world_key, entity.guid)
      :error = Instance.get_entity(world_key, entity.guid)
    end

    test "update_entity_position/3 updates position", %{world_key: world_key} do
      entity = %Entity{
        guid: 2_000_003,
        type: :npc,
        name: "Test NPC",
        position: {700.0, 700.0, 700.0},
        health: 100,
        max_health: 100
      }

      Instance.add_entity(world_key, entity)
      new_pos = {800.0, 800.0, 800.0}
      :ok = Instance.update_entity_position(world_key, entity.guid, new_pos)

      {:ok, updated} = Instance.get_entity(world_key, entity.guid)
      assert updated.position == new_pos
    end

    test "entities_in_range/3 finds nearby entities", %{world_key: world_key} do
      # Add entities at known positions
      entity1 = %Entity{
        guid: 2_000_010,
        type: :npc,
        name: "Near NPC",
        position: {1000.0, 1000.0, 1000.0},
        health: 100,
        max_health: 100
      }

      entity2 = %Entity{
        guid: 2_000_011,
        type: :npc,
        name: "Far NPC",
        position: {2000.0, 2000.0, 2000.0},
        health: 100,
        max_health: 100
      }

      Instance.add_entity(world_key, entity1)
      Instance.add_entity(world_key, entity2)

      # Search around entity1's position
      nearby = Instance.entities_in_range(world_key, {1000.0, 1000.0, 1000.0}, 50.0)

      assert Enum.any?(nearby, fn e -> e.guid == entity1.guid end)
      refute Enum.any?(nearby, fn e -> e.guid == entity2.guid end)
    end

    test "player_count/1 tracks player entities", %{world_key: world_key} do
      initial_count = Instance.player_count(world_key)

      player = %Entity{
        guid: 2_000_020,
        type: :player,
        name: "Test Player",
        position: {1100.0, 1100.0, 1100.0},
        health: 1000,
        max_health: 1000
      }

      Instance.add_entity(world_key, player)
      Process.sleep(50)

      assert Instance.player_count(world_key) == initial_count + 1

      Instance.remove_entity(world_key, player.guid)
      Process.sleep(50)

      assert Instance.player_count(world_key) == initial_count
    end
  end
end
