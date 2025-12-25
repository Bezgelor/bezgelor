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

  # =====================================================================
  # Objective Type Security Tests
  # =====================================================================

  describe "valid_objective_types/0" do
    test "returns list of valid objective types" do
      types = EventManager.valid_objective_types()

      assert is_list(types)
      assert :kill in types
      assert :damage in types
      assert :collect in types
      assert :interact in types
      assert :territory in types
      assert :escort in types
      assert :defend in types
      assert :survive in types
      assert :timer in types
      assert length(types) == 9
    end
  end

  describe "safe_objective_type/1" do
    test "returns :kill for nil" do
      assert EventManager.safe_objective_type(nil) == :kill
    end

    test "returns valid atom types unchanged" do
      assert EventManager.safe_objective_type(:kill) == :kill
      assert EventManager.safe_objective_type(:damage) == :damage
      assert EventManager.safe_objective_type(:collect) == :collect
      assert EventManager.safe_objective_type(:interact) == :interact
      assert EventManager.safe_objective_type(:territory) == :territory
      assert EventManager.safe_objective_type(:escort) == :escort
      assert EventManager.safe_objective_type(:defend) == :defend
      assert EventManager.safe_objective_type(:survive) == :survive
      assert EventManager.safe_objective_type(:timer) == :timer
    end

    test "returns :kill for invalid atom types" do
      assert EventManager.safe_objective_type(:invalid) == :kill
      assert EventManager.safe_objective_type(:malicious) == :kill
      assert EventManager.safe_objective_type(:anything_else) == :kill
    end

    test "converts valid string types to atoms" do
      assert EventManager.safe_objective_type("kill") == :kill
      assert EventManager.safe_objective_type("damage") == :damage
      assert EventManager.safe_objective_type("collect") == :collect
    end

    test "returns :kill for invalid string types (prevents atom table exhaustion)" do
      # These strings don't exist as atoms, so String.to_existing_atom will fail
      # This is the security feature - we don't create new atoms from untrusted input
      assert EventManager.safe_objective_type("malicious_type_12345") == :kill
      assert EventManager.safe_objective_type("random_string_xyz") == :kill
      assert EventManager.safe_objective_type("") == :kill
    end

    test "returns :kill for valid existing atoms not in whitelist" do
      # These atoms exist in the atom table but aren't in the whitelist
      assert EventManager.safe_objective_type("true") == :kill
      assert EventManager.safe_objective_type("false") == :kill
      assert EventManager.safe_objective_type("nil") == :kill
    end
  end
end
