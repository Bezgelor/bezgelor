defmodule BezgelorWorld.World.InstanceSupervisorTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.World.{Instance, InstanceSupervisor}
  alias BezgelorCore.Entity

  setup do
    # InstanceSupervisor is already started by the application
    # Clean up any instances from previous tests
    for {world_id, instance_id, _pid} <- InstanceSupervisor.list_instances() do
      InstanceSupervisor.stop_instance(world_id, instance_id)
    end

    # Give time for processes to terminate
    Process.sleep(10)

    :ok
  end

  describe "start_instance/3" do
    test "starts a new world instance" do
      world_id = System.unique_integer([:positive])

      {:ok, pid} = InstanceSupervisor.start_instance(world_id, 1, %{name: "Test"})

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns existing pid if already started" do
      world_id = System.unique_integer([:positive])

      {:ok, pid1} = InstanceSupervisor.start_instance(world_id, 1)
      {:ok, pid2} = InstanceSupervisor.start_instance(world_id, 1)

      assert pid1 == pid2
    end
  end

  describe "stop_instance/2" do
    test "stops a running instance" do
      world_id = System.unique_integer([:positive])

      {:ok, pid} = InstanceSupervisor.start_instance(world_id, 1)
      assert Process.alive?(pid)

      :ok = InstanceSupervisor.stop_instance(world_id, 1)

      # Give time for process to terminate
      Process.sleep(10)
      refute Process.alive?(pid)
    end

    test "returns error for nonexistent instance" do
      assert {:error, :not_found} = InstanceSupervisor.stop_instance(99999, 1)
    end
  end

  describe "get_or_start_instance/3" do
    test "starts instance if not running" do
      world_id = System.unique_integer([:positive])

      {:ok, pid} = InstanceSupervisor.get_or_start_instance(world_id, 1)

      assert is_pid(pid)
    end

    test "returns existing instance if running" do
      world_id = System.unique_integer([:positive])

      {:ok, pid1} = InstanceSupervisor.start_instance(world_id, 1)
      {:ok, pid2} = InstanceSupervisor.get_or_start_instance(world_id, 1)

      assert pid1 == pid2
    end
  end

  describe "list_instances/0" do
    test "returns empty list when no instances" do
      assert InstanceSupervisor.list_instances() == []
    end

    test "returns all running instances" do
      world1 = System.unique_integer([:positive])
      world2 = System.unique_integer([:positive])

      {:ok, _} = InstanceSupervisor.start_instance(world1, 1)
      {:ok, _} = InstanceSupervisor.start_instance(world1, 2)
      {:ok, _} = InstanceSupervisor.start_instance(world2, 1)

      instances = InstanceSupervisor.list_instances()

      assert length(instances) == 3
    end
  end

  describe "list_instances_for_world/1" do
    test "returns instances for specific world" do
      world1 = System.unique_integer([:positive])
      world2 = System.unique_integer([:positive])

      {:ok, _} = InstanceSupervisor.start_instance(world1, 1)
      {:ok, _} = InstanceSupervisor.start_instance(world1, 2)
      {:ok, _} = InstanceSupervisor.start_instance(world2, 1)

      instances = InstanceSupervisor.list_instances_for_world(world1)

      assert length(instances) == 2
      assert Enum.all?(instances, fn {id, _pid} -> id in [1, 2] end)
    end
  end

  describe "instance_count/0" do
    test "returns count of running instances" do
      assert InstanceSupervisor.instance_count() == 0

      world = System.unique_integer([:positive])
      {:ok, _} = InstanceSupervisor.start_instance(world, 1)
      {:ok, _} = InstanceSupervisor.start_instance(world, 2)

      assert InstanceSupervisor.instance_count() == 2
    end
  end

  describe "find_best_instance/2" do
    test "returns instance with lowest player count" do
      world = System.unique_integer([:positive])

      {:ok, _} = InstanceSupervisor.start_instance(world, 1)
      {:ok, _} = InstanceSupervisor.start_instance(world, 2)

      # Add players to instance 1
      Instance.add_entity({world, 1}, %Entity{guid: 1, type: :player})
      Instance.add_entity({world, 1}, %Entity{guid: 2, type: :player})

      # Add one player to instance 2
      Instance.add_entity({world, 2}, %Entity{guid: 3, type: :player})

      # Give time for casts to process
      Process.sleep(10)

      {:ok, best_id} = InstanceSupervisor.find_best_instance(world)
      assert best_id == 2
    end

    test "returns error when no instances exist" do
      world = System.unique_integer([:positive])

      assert {:error, :no_instance} = InstanceSupervisor.find_best_instance(world)
    end

    test "excludes instances at capacity" do
      world = System.unique_integer([:positive])

      {:ok, _} = InstanceSupervisor.start_instance(world, 1)
      {:ok, _} = InstanceSupervisor.start_instance(world, 2)

      # Fill instance 1 beyond capacity of 2
      Instance.add_entity({world, 1}, %Entity{guid: 1, type: :player})
      Instance.add_entity({world, 1}, %Entity{guid: 2, type: :player})
      Instance.add_entity({world, 1}, %Entity{guid: 3, type: :player})

      # Instance 2 has space
      Instance.add_entity({world, 2}, %Entity{guid: 4, type: :player})

      Process.sleep(10)

      # With max 2 players, only instance 2 should be available
      {:ok, best_id} = InstanceSupervisor.find_best_instance(world, 2)
      assert best_id == 2
    end
  end
end
