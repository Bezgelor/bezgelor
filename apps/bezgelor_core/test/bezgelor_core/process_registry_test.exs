defmodule BezgelorCore.ProcessRegistryTest do
  use ExUnit.Case, async: false

  alias BezgelorCore.ProcessRegistry

  setup do
    # Clean up any registered processes from previous tests
    for {id, _pid} <- ProcessRegistry.list(:test_type) do
      ProcessRegistry.unregister(:test_type, id)
    end

    :ok
  end

  describe "register/3" do
    test "registers current process with type and id" do
      assert {:ok, pid} = ProcessRegistry.register(:test_type, :test_id)
      assert pid == self()
    end

    test "registers with metadata" do
      assert {:ok, _pid} = ProcessRegistry.register(:test_type, :with_meta, %{name: "test"})

      {:ok, _pid, meta} = ProcessRegistry.lookup_with_meta(:test_type, :with_meta)
      assert meta == %{name: "test"}
    end

    test "returns error when already registered" do
      {:ok, _} = ProcessRegistry.register(:test_type, :duplicate)

      task =
        Task.async(fn ->
          ProcessRegistry.register(:test_type, :duplicate)
        end)

      assert {:error, {:already_registered, _pid}} = Task.await(task)
    end
  end

  describe "lookup/2" do
    test "returns {:ok, pid} when found" do
      {:ok, _} = ProcessRegistry.register(:test_type, :lookup_test)

      assert {:ok, pid} = ProcessRegistry.lookup(:test_type, :lookup_test)
      assert pid == self()
    end

    test "returns :error when not found" do
      assert :error = ProcessRegistry.lookup(:test_type, :nonexistent)
    end
  end

  describe "lookup_with_meta/2" do
    test "returns {:ok, pid, metadata} when found" do
      {:ok, _} = ProcessRegistry.register(:test_type, :meta_test, %{level: 10})

      assert {:ok, pid, meta} = ProcessRegistry.lookup_with_meta(:test_type, :meta_test)
      assert pid == self()
      assert meta == %{level: 10}
    end

    test "returns :error when not found" do
      assert :error = ProcessRegistry.lookup_with_meta(:test_type, :nonexistent)
    end
  end

  describe "whereis/2" do
    test "returns pid when found" do
      {:ok, _} = ProcessRegistry.register(:test_type, :whereis_test)

      assert ProcessRegistry.whereis(:test_type, :whereis_test) == self()
    end

    test "returns nil when not found" do
      assert ProcessRegistry.whereis(:test_type, :nonexistent) == nil
    end
  end

  describe "list/1" do
    test "returns empty list when no processes registered" do
      assert ProcessRegistry.list(:empty_type) == []
    end

    test "returns all processes of type" do
      # Start processes that register themselves
      task1 =
        Task.async(fn ->
          {:ok, _} = ProcessRegistry.register(:list_type, :id1)
          Process.sleep(:infinity)
        end)

      task2 =
        Task.async(fn ->
          {:ok, _} = ProcessRegistry.register(:list_type, :id2)
          Process.sleep(:infinity)
        end)

      # Give them time to register
      Process.sleep(50)

      result = ProcessRegistry.list(:list_type)
      assert length(result) == 2

      ids = Enum.map(result, fn {id, _pid} -> id end) |> Enum.sort()
      assert ids == [:id1, :id2]

      # Cleanup
      Task.shutdown(task1, :brutal_kill)
      Task.shutdown(task2, :brutal_kill)
    end
  end

  describe "list_with_meta/1" do
    test "returns processes with metadata" do
      task =
        Task.async(fn ->
          {:ok, _} = ProcessRegistry.register(:meta_list_type, :id1, %{name: "Alice"})
          Process.sleep(:infinity)
        end)

      Process.sleep(50)

      result = ProcessRegistry.list_with_meta(:meta_list_type)
      assert length(result) == 1

      [{id, _pid, meta}] = result
      assert id == :id1
      assert meta == %{name: "Alice"}

      Task.shutdown(task, :brutal_kill)
    end
  end

  describe "count/1" do
    test "returns 0 when no processes registered" do
      assert ProcessRegistry.count(:count_empty_type) == 0
    end

    test "returns count of registered processes" do
      task1 =
        Task.async(fn ->
          {:ok, _} = ProcessRegistry.register(:count_type, :c1)
          Process.sleep(:infinity)
        end)

      task2 =
        Task.async(fn ->
          {:ok, _} = ProcessRegistry.register(:count_type, :c2)
          Process.sleep(:infinity)
        end)

      Process.sleep(50)

      assert ProcessRegistry.count(:count_type) == 2

      Task.shutdown(task1, :brutal_kill)
      Task.shutdown(task2, :brutal_kill)
    end
  end

  describe "unregister/2" do
    test "unregisters a process" do
      {:ok, _} = ProcessRegistry.register(:test_type, :unregister_test)
      assert {:ok, _} = ProcessRegistry.lookup(:test_type, :unregister_test)

      :ok = ProcessRegistry.unregister(:test_type, :unregister_test)
      assert :error = ProcessRegistry.lookup(:test_type, :unregister_test)
    end
  end

  describe "update_meta/3" do
    test "updates metadata for registered process" do
      {:ok, _} = ProcessRegistry.register(:test_type, :update_test, %{level: 1})

      {:ok, new_meta} =
        ProcessRegistry.update_meta(:test_type, :update_test, fn meta ->
          %{meta | level: meta.level + 1}
        end)

      assert new_meta == %{level: 2}

      {:ok, _pid, meta} = ProcessRegistry.lookup_with_meta(:test_type, :update_test)
      assert meta == %{level: 2}
    end

    test "returns error when process not found" do
      assert :error = ProcessRegistry.update_meta(:test_type, :nonexistent, fn m -> m end)
    end
  end

  describe "broadcast/2" do
    test "sends message to all processes of type" do
      parent = self()

      task1 =
        Task.async(fn ->
          {:ok, _} = ProcessRegistry.register(:broadcast_type, :b1)

          receive do
            :test_message -> send(parent, {:received, :b1})
          end
        end)

      task2 =
        Task.async(fn ->
          {:ok, _} = ProcessRegistry.register(:broadcast_type, :b2)

          receive do
            :test_message -> send(parent, {:received, :b2})
          end
        end)

      Process.sleep(50)

      count = ProcessRegistry.broadcast(:broadcast_type, :test_message)
      assert count == 2

      assert_receive {:received, :b1}, 100
      assert_receive {:received, :b2}, 100

      Task.await(task1)
      Task.await(task2)
    end

    test "returns 0 when no processes registered" do
      assert ProcessRegistry.broadcast(:empty_broadcast_type, :msg) == 0
    end
  end

  describe "automatic unregistration on process death" do
    test "process is unregistered when it dies" do
      task =
        Task.async(fn ->
          {:ok, _} = ProcessRegistry.register(:death_type, :dying_process)
          # Exit normally
        end)

      Task.await(task)

      # Give registry time to clean up
      Process.sleep(50)

      assert :error = ProcessRegistry.lookup(:death_type, :dying_process)
    end
  end
end
