defmodule BezgelorWorld.Zone.InstanceSupervisorTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.Zone.{Instance, InstanceSupervisor}
  alias BezgelorCore.Entity

  setup do
    # InstanceSupervisor is already started by the application
    # Clean up any instances from previous tests
    for {zone_id, instance_id, _pid} <- InstanceSupervisor.list_instances() do
      InstanceSupervisor.stop_instance(zone_id, instance_id)
    end

    :ok
  end

  describe "start_instance/3" do
    test "starts a new zone instance" do
      zone_id = System.unique_integer([:positive])

      {:ok, pid} = InstanceSupervisor.start_instance(zone_id, 1, %{name: "Test"})

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns existing pid if already started" do
      zone_id = System.unique_integer([:positive])

      {:ok, pid1} = InstanceSupervisor.start_instance(zone_id, 1)
      {:ok, pid2} = InstanceSupervisor.start_instance(zone_id, 1)

      assert pid1 == pid2
    end
  end

  describe "stop_instance/2" do
    test "stops a running instance" do
      zone_id = System.unique_integer([:positive])

      {:ok, pid} = InstanceSupervisor.start_instance(zone_id, 1)
      assert Process.alive?(pid)

      :ok = InstanceSupervisor.stop_instance(zone_id, 1)

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
      zone_id = System.unique_integer([:positive])

      {:ok, pid} = InstanceSupervisor.get_or_start_instance(zone_id, 1)

      assert is_pid(pid)
    end

    test "returns existing instance if running" do
      zone_id = System.unique_integer([:positive])

      {:ok, pid1} = InstanceSupervisor.start_instance(zone_id, 1)
      {:ok, pid2} = InstanceSupervisor.get_or_start_instance(zone_id, 1)

      assert pid1 == pid2
    end
  end

  describe "list_instances/0" do
    test "returns empty list when no instances" do
      assert InstanceSupervisor.list_instances() == []
    end

    test "returns all running instances" do
      zone1 = System.unique_integer([:positive])
      zone2 = System.unique_integer([:positive])

      {:ok, _} = InstanceSupervisor.start_instance(zone1, 1)
      {:ok, _} = InstanceSupervisor.start_instance(zone1, 2)
      {:ok, _} = InstanceSupervisor.start_instance(zone2, 1)

      instances = InstanceSupervisor.list_instances()

      assert length(instances) == 3
    end
  end

  describe "list_instances_for_zone/1" do
    test "returns instances for specific zone" do
      zone1 = System.unique_integer([:positive])
      zone2 = System.unique_integer([:positive])

      {:ok, _} = InstanceSupervisor.start_instance(zone1, 1)
      {:ok, _} = InstanceSupervisor.start_instance(zone1, 2)
      {:ok, _} = InstanceSupervisor.start_instance(zone2, 1)

      instances = InstanceSupervisor.list_instances_for_zone(zone1)

      assert length(instances) == 2
      assert Enum.all?(instances, fn {id, _pid} -> id in [1, 2] end)
    end
  end

  describe "instance_count/0" do
    test "returns count of running instances" do
      assert InstanceSupervisor.instance_count() == 0

      zone = System.unique_integer([:positive])
      {:ok, _} = InstanceSupervisor.start_instance(zone, 1)
      {:ok, _} = InstanceSupervisor.start_instance(zone, 2)

      assert InstanceSupervisor.instance_count() == 2
    end
  end

  describe "find_best_instance/2" do
    test "returns instance with lowest player count" do
      zone = System.unique_integer([:positive])

      {:ok, _} = InstanceSupervisor.start_instance(zone, 1)
      {:ok, _} = InstanceSupervisor.start_instance(zone, 2)

      # Add players to instance 1
      Instance.add_entity({zone, 1}, %Entity{guid: 1, type: :player})
      Instance.add_entity({zone, 1}, %Entity{guid: 2, type: :player})

      # Add one player to instance 2
      Instance.add_entity({zone, 2}, %Entity{guid: 3, type: :player})

      # Give time for casts to process
      Process.sleep(10)

      {:ok, best_id} = InstanceSupervisor.find_best_instance(zone)
      assert best_id == 2
    end

    test "returns error when no instances exist" do
      zone = System.unique_integer([:positive])

      assert {:error, :no_instance} = InstanceSupervisor.find_best_instance(zone)
    end

    test "excludes instances at capacity" do
      zone = System.unique_integer([:positive])

      {:ok, _} = InstanceSupervisor.start_instance(zone, 1)
      {:ok, _} = InstanceSupervisor.start_instance(zone, 2)

      # Fill instance 1 beyond capacity of 2
      Instance.add_entity({zone, 1}, %Entity{guid: 1, type: :player})
      Instance.add_entity({zone, 1}, %Entity{guid: 2, type: :player})
      Instance.add_entity({zone, 1}, %Entity{guid: 3, type: :player})

      # Instance 2 has space
      Instance.add_entity({zone, 2}, %Entity{guid: 4, type: :player})

      Process.sleep(10)

      # With max 2 players, only instance 2 should be available
      {:ok, best_id} = InstanceSupervisor.find_best_instance(zone, 2)
      assert best_id == 2
    end
  end
end
