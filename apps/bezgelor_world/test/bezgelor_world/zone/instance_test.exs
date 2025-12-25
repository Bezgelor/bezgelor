defmodule BezgelorWorld.Zone.InstanceTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.World.{Instance, InstanceSupervisor}
  alias BezgelorCore.Entity

  setup do
    # InstanceSupervisor is already started by the application
    # Generate unique world/instance IDs for each test
    # World.Instance is keyed by world_id
    world_id = System.unique_integer([:positive])
    instance_id = 1

    world_data = %{
      id: world_id,
      name: "Test World",
      min_level: 1,
      max_level: 10
    }

    {:ok, pid} = InstanceSupervisor.start_instance(world_id, instance_id, world_data)

    on_exit(fn ->
      InstanceSupervisor.stop_instance(world_id, instance_id)
    end)

    %{world_id: world_id, instance_id: instance_id, pid: pid}
  end

  describe "add_entity/2" do
    test "adds player entity to world instance", %{world_id: world_id, instance_id: instance_id} do
      entity = %Entity{
        guid: 12345,
        type: :player,
        name: "TestPlayer",
        position: {100.0, 50.0, 200.0}
      }

      :ok = Instance.add_entity({world_id, instance_id}, entity)

      {:ok, retrieved} = Instance.get_entity({world_id, instance_id}, 12345)
      assert retrieved.name == "TestPlayer"
    end

    test "adds creature entity to world instance", %{world_id: world_id, instance_id: instance_id} do
      entity = %Entity{
        guid: 99999,
        type: :creature,
        name: "TestCreature",
        position: {0.0, 0.0, 0.0}
      }

      :ok = Instance.add_entity({world_id, instance_id}, entity)

      {:ok, retrieved} = Instance.get_entity({world_id, instance_id}, 99999)
      assert retrieved.name == "TestCreature"
    end
  end

  describe "remove_entity/2" do
    test "removes entity from world instance", %{world_id: world_id, instance_id: instance_id} do
      entity = %Entity{guid: 12345, type: :player, name: "Test"}

      Instance.add_entity({world_id, instance_id}, entity)
      Instance.remove_entity({world_id, instance_id}, 12345)

      assert :error = Instance.get_entity({world_id, instance_id}, 12345)
    end
  end

  describe "get_entity/2" do
    test "returns :error for nonexistent entity", %{world_id: world_id, instance_id: instance_id} do
      assert :error = Instance.get_entity({world_id, instance_id}, 99999)
    end
  end

  describe "update_entity/3" do
    test "updates entity state", %{world_id: world_id, instance_id: instance_id} do
      entity = %Entity{guid: 12345, type: :player, name: "Test", health: 100}

      Instance.add_entity({world_id, instance_id}, entity)

      :ok =
        Instance.update_entity({world_id, instance_id}, 12345, fn e ->
          %{e | health: 50}
        end)

      {:ok, updated} = Instance.get_entity({world_id, instance_id}, 12345)
      assert updated.health == 50
    end

    test "returns :error for nonexistent entity", %{world_id: world_id, instance_id: instance_id} do
      assert :error = Instance.update_entity({world_id, instance_id}, 99999, fn e -> e end)
    end
  end

  describe "entities_in_range/3" do
    test "finds entities within range", %{world_id: world_id, instance_id: instance_id} do
      # Add entities at various positions
      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 1,
        type: :player,
        position: {0.0, 0.0, 0.0}
      })

      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 2,
        type: :player,
        position: {50.0, 0.0, 0.0}
      })

      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 3,
        type: :player,
        position: {200.0, 0.0, 0.0}
      })

      # Find entities within 100 units of origin
      entities = Instance.entities_in_range({world_id, instance_id}, {0.0, 0.0, 0.0}, 100.0)

      guids = Enum.map(entities, & &1.guid) |> Enum.sort()
      assert guids == [1, 2]
    end

    test "returns empty list when no entities in range", %{
      world_id: world_id,
      instance_id: instance_id
    } do
      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 1,
        type: :player,
        position: {1000.0, 1000.0, 1000.0}
      })

      entities = Instance.entities_in_range({world_id, instance_id}, {0.0, 0.0, 0.0}, 10.0)
      assert entities == []
    end
  end

  describe "list_players/1" do
    test "returns only player entities", %{world_id: world_id, instance_id: instance_id} do
      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 1,
        type: :player,
        name: "Player1"
      })

      Instance.add_entity({world_id, instance_id}, %Entity{guid: 2, type: :creature, name: "Mob"})

      Instance.add_entity({world_id, instance_id}, %Entity{
        guid: 3,
        type: :player,
        name: "Player2"
      })

      players = Instance.list_players({world_id, instance_id})

      assert length(players) == 2
      assert Enum.all?(players, fn p -> p.type == :player end)
    end
  end

  describe "player_count/1" do
    test "returns count of players", %{world_id: world_id, instance_id: instance_id} do
      assert Instance.player_count({world_id, instance_id}) == 0

      Instance.add_entity({world_id, instance_id}, %Entity{guid: 1, type: :player})
      Instance.add_entity({world_id, instance_id}, %Entity{guid: 2, type: :creature})
      Instance.add_entity({world_id, instance_id}, %Entity{guid: 3, type: :player})

      # Give time for casts to process
      Process.sleep(10)

      assert Instance.player_count({world_id, instance_id}) == 2
    end
  end

  describe "info/1" do
    test "returns world instance information", %{world_id: world_id, instance_id: instance_id} do
      Instance.add_entity({world_id, instance_id}, %Entity{guid: 1, type: :player})
      Instance.add_entity({world_id, instance_id}, %Entity{guid: 2, type: :creature})

      # Give time for casts to process
      Process.sleep(10)

      info = Instance.info({world_id, instance_id})

      assert info.world_id == world_id
      assert info.instance_id == instance_id
      assert info.world_name == "Test World"
      assert info.player_count == 1
      assert info.creature_count == 1
      assert info.total_entities == 2
    end
  end

  describe "lazy loading (Phase 3)" do
    test "lazy_loading option defers spawn loading" do
      # Create a lazy-loading instance
      world_id = System.unique_integer([:positive])
      instance_id = 1
      world_data = %{name: "Lazy Test World"}

      {:ok, pid} =
        Instance.start_link(
          world_id: world_id,
          instance_id: instance_id,
          world_data: world_data,
          lazy_loading: true
        )

      # Give time for init to complete
      Process.sleep(50)

      # Verify instance started but spawns not loaded
      state = :sys.get_state(pid)
      assert state.lazy_loading == true
      assert state.spawns_loaded == false

      # Clean up
      GenServer.stop(pid)
    end

    test "first player entering triggers spawn loading in lazy mode" do
      # Create a lazy-loading instance
      world_id = System.unique_integer([:positive])
      instance_id = 1
      world_data = %{name: "Lazy Test World"}

      {:ok, pid} =
        Instance.start_link(
          world_id: world_id,
          instance_id: instance_id,
          world_data: world_data,
          lazy_loading: true
        )

      Process.sleep(50)

      # Verify spawns not loaded initially
      state = :sys.get_state(pid)
      assert state.spawns_loaded == false

      # Add a player
      player = %Entity{guid: 12345, type: :player, name: "Test", position: {0.0, 0.0, 0.0}}
      Instance.add_entity(pid, player)
      Process.sleep(50)

      # Verify spawns are now loaded
      state = :sys.get_state(pid)
      assert state.spawns_loaded == true
      assert MapSet.size(state.players) == 1

      # Clean up
      GenServer.stop(pid)
    end

    test "last player leaving starts idle timeout in lazy mode" do
      # Create a lazy-loading instance
      world_id = System.unique_integer([:positive])
      instance_id = 1
      world_data = %{name: "Lazy Test World"}

      {:ok, pid} =
        Instance.start_link(
          world_id: world_id,
          instance_id: instance_id,
          world_data: world_data,
          lazy_loading: true
        )

      Process.sleep(50)

      # Add and then remove a player
      player = %Entity{guid: 12345, type: :player, name: "Test", position: {0.0, 0.0, 0.0}}
      Instance.add_entity(pid, player)
      Process.sleep(50)

      Instance.remove_entity(pid, 12345)
      Process.sleep(50)

      # Verify idle timeout is set
      state = :sys.get_state(pid)
      assert state.idle_timeout_ref != nil
      assert state.last_player_left_at != nil
      assert MapSet.size(state.players) == 0

      # Clean up
      GenServer.stop(pid)
    end

    test "player re-entering cancels idle timeout" do
      # Create a lazy-loading instance
      world_id = System.unique_integer([:positive])
      instance_id = 1
      world_data = %{name: "Lazy Test World"}

      {:ok, pid} =
        Instance.start_link(
          world_id: world_id,
          instance_id: instance_id,
          world_data: world_data,
          lazy_loading: true
        )

      Process.sleep(50)

      # Add, remove, then add player again
      player1 = %Entity{guid: 12345, type: :player, name: "Test1", position: {0.0, 0.0, 0.0}}
      Instance.add_entity(pid, player1)
      Process.sleep(50)

      Instance.remove_entity(pid, 12345)
      Process.sleep(50)

      # Verify idle timeout is set
      state = :sys.get_state(pid)
      assert state.idle_timeout_ref != nil

      # Add another player
      player2 = %Entity{guid: 67890, type: :player, name: "Test2", position: {0.0, 0.0, 0.0}}
      Instance.add_entity(pid, player2)
      Process.sleep(50)

      # Verify idle timeout is cancelled
      state = :sys.get_state(pid)
      assert state.idle_timeout_ref == nil
      assert state.last_player_left_at == nil

      # Clean up
      GenServer.stop(pid)
    end

    test "non-lazy instances don't set idle timeout" do
      # Use the instance from setup (non-lazy)
      world_id = System.unique_integer([:positive])
      instance_id = 1
      world_data = %{name: "Non-Lazy Test World"}

      {:ok, pid} =
        Instance.start_link(
          world_id: world_id,
          instance_id: instance_id,
          world_data: world_data,
          lazy_loading: false
        )

      # Wait for spawns to load
      Process.sleep(100)

      # Add and remove a player
      player = %Entity{guid: 12345, type: :player, name: "Test", position: {0.0, 0.0, 0.0}}
      Instance.add_entity(pid, player)
      Process.sleep(50)

      Instance.remove_entity(pid, 12345)
      Process.sleep(50)

      # Verify no idle timeout in non-lazy mode
      state = :sys.get_state(pid)
      assert state.lazy_loading == false
      assert state.idle_timeout_ref == nil

      # Clean up
      GenServer.stop(pid)
    end

    test "rapid player enter/exit maintains correct state" do
      # Edge case: rapid add/remove cycles
      world_id = System.unique_integer([:positive])
      instance_id = 1
      world_data = %{name: "Rapid Test World"}

      {:ok, pid} =
        Instance.start_link(
          world_id: world_id,
          instance_id: instance_id,
          world_data: world_data,
          lazy_loading: true
        )

      Process.sleep(50)

      # Rapidly add and remove multiple players
      for i <- 1..10 do
        player = %Entity{guid: i, type: :player, name: "Player#{i}", position: {0.0, 0.0, 0.0}}
        Instance.add_entity(pid, player)
      end

      Process.sleep(50)

      # All 10 players should be present
      state = :sys.get_state(pid)
      assert MapSet.size(state.players) == 10
      assert state.spawns_loaded == true

      # Rapidly remove all players
      for i <- 1..10 do
        Instance.remove_entity(pid, i)
      end

      Process.sleep(50)

      # No players, idle timeout should be set
      state = :sys.get_state(pid)
      assert MapSet.size(state.players) == 0
      assert state.idle_timeout_ref != nil

      # Clean up
      GenServer.stop(pid)
    end

    test "concurrent first player entries only load spawns once" do
      # Edge case: multiple players enter before spawns finish loading
      world_id = System.unique_integer([:positive])
      instance_id = 1
      world_data = %{name: "Concurrent Test World"}

      {:ok, pid} =
        Instance.start_link(
          world_id: world_id,
          instance_id: instance_id,
          world_data: world_data,
          lazy_loading: true
        )

      Process.sleep(50)

      # Add multiple players "simultaneously" (as close as we can in test)
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            player = %Entity{guid: i, type: :player, name: "Player#{i}", position: {0.0, 0.0, 0.0}}
            Instance.add_entity(pid, player)
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, &Task.await/1)
      Process.sleep(100)

      # Verify state is consistent
      state = :sys.get_state(pid)
      assert state.spawns_loaded == true
      assert MapSet.size(state.players) == 5

      # Clean up
      GenServer.stop(pid)
    end

    test "adding creature does not trigger spawn loading in lazy mode" do
      # Edge case: only players should trigger spawn loading
      world_id = System.unique_integer([:positive])
      instance_id = 1
      world_data = %{name: "Creature Test World"}

      {:ok, pid} =
        Instance.start_link(
          world_id: world_id,
          instance_id: instance_id,
          world_data: world_data,
          lazy_loading: true
        )

      Process.sleep(50)

      # Add a creature (not a player)
      creature = %Entity{guid: 99999, type: :creature, name: "TestMob", position: {0.0, 0.0, 0.0}}
      Instance.add_entity(pid, creature)
      Process.sleep(50)

      # Spawns should NOT be loaded - only players trigger loading
      state = :sys.get_state(pid)
      assert state.spawns_loaded == false
      assert MapSet.size(state.creatures) == 1

      # Clean up
      GenServer.stop(pid)
    end

    test "removing non-player entity does not affect idle timeout" do
      # Edge case: only player removal should trigger idle timeout
      world_id = System.unique_integer([:positive])
      instance_id = 1
      world_data = %{name: "Entity Test World"}

      {:ok, pid} =
        Instance.start_link(
          world_id: world_id,
          instance_id: instance_id,
          world_data: world_data,
          lazy_loading: true
        )

      Process.sleep(50)

      # Add a player and a creature
      player = %Entity{guid: 1, type: :player, name: "Player", position: {0.0, 0.0, 0.0}}
      creature = %Entity{guid: 2, type: :creature, name: "Mob", position: {0.0, 0.0, 0.0}}
      Instance.add_entity(pid, player)
      Instance.add_entity(pid, creature)
      Process.sleep(50)

      # Remove the creature
      Instance.remove_entity(pid, 2)
      Process.sleep(50)

      # Idle timeout should NOT be set (player still present)
      state = :sys.get_state(pid)
      assert state.idle_timeout_ref == nil
      assert MapSet.size(state.players) == 1

      # Clean up
      GenServer.stop(pid)
    end
  end
end
