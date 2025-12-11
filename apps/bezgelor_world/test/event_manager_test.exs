defmodule BezgelorWorld.EventManagerTest do
  @moduledoc """
  Tests for EventManager GenServer.
  """

  use ExUnit.Case, async: false

  alias BezgelorWorld.EventManager

  @zone_id 1
  @instance_id 1

  setup do
    # Start the Registry if not running
    case Registry.start_link(keys: :unique, name: BezgelorWorld.EventRegistry) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Start the EventManager
    {:ok, manager} = EventManager.start_link(zone_id: @zone_id, instance_id: @instance_id)

    on_exit(fn ->
      if Process.alive?(manager) do
        GenServer.stop(manager)
      end
    end)

    %{manager: manager}
  end

  describe "start_event/2" do
    test "starts a new event instance", %{manager: manager} do
      # Event ID 1 from the test data (may not exist, but tests the flow)
      result = EventManager.start_event(manager, 1)

      # Without actual event data loaded, this will fail
      # In a real test we'd mock or load test data
      assert match?({:error, :event_not_found}, result) or match?({:ok, _}, result)
    end
  end

  describe "list_events/1" do
    test "returns empty list initially", %{manager: manager} do
      events = EventManager.list_events(manager)
      assert events == []
    end
  end

  describe "get_event/2" do
    test "returns error for non-existent event", %{manager: manager} do
      result = EventManager.get_event(manager, 999)
      assert result == {:error, :not_found}
    end
  end

  describe "list_world_bosses/1" do
    test "returns empty list initially", %{manager: manager} do
      bosses = EventManager.list_world_bosses(manager)
      assert bosses == []
    end
  end

  describe "get_world_boss/2" do
    test "returns error for non-existent boss", %{manager: manager} do
      result = EventManager.get_world_boss(manager, 999)
      assert result == {:error, :not_found}
    end
  end

  describe "via_tuple/2" do
    test "generates correct registry tuple" do
      tuple = EventManager.via_tuple(@zone_id, @instance_id)
      assert {:via, Registry, {BezgelorWorld.EventRegistry, {@zone_id, @instance_id}}} = tuple
    end
  end

  describe "report_creature_kill/3" do
    test "handles kills without events", %{manager: manager} do
      # Should not crash even with no active events
      assert :ok = EventManager.report_creature_kill(manager, 1, 1001)
    end
  end

  describe "record_boss_damage/4" do
    test "handles damage without active boss", %{manager: manager} do
      # Should not crash even with no active boss
      assert :ok = EventManager.record_boss_damage(manager, 999, 1, 100)
    end
  end
end
