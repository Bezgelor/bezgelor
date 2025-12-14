# Phase 2: Trigger Volumes Implementation Plan

**Date:** 2025-12-14
**Status:** Ready for Implementation
**Prerequisite:** Phase 1 complete (Core Teleportation)

## Goal

Implement trigger volume detection that fires events when players enter specific areas. This enables quest-gated teleportation (Phase 3) by detecting when players step on teleport pads.

## Architecture

```
Movement Handler → TriggerManager.check_triggers → EventDispatcher.dispatch_enter_area
                                                          ↓
                                           Quest/Path Managers receive event
```

**Flow:**
1. Zone loads trigger volumes from world_locations.json on init
2. MovementHandler calls TriggerManager after position updates
3. TriggerManager checks if player entered any new triggers
4. If entered, fires `:enter_area` event via EventDispatcher
5. Quest system receives event for objective progress

## Tech Stack

- **Module:** `BezgelorWorld.TriggerManager`
- **Tests:** `apps/bezgelor_world/test/trigger_manager_test.exs`
- **Integration:** Hook into `MovementHandler` and `Zone.Instance`
- **Data:** World locations from `BezgelorData.world_locations_for_zone/1`

## Tasks

### Task 1: Create TriggerManager test file

**File:** `apps/bezgelor_world/test/trigger_manager_test.exs`

```elixir
defmodule BezgelorWorld.TriggerManagerTest do
  use ExUnit.Case, async: true

  alias BezgelorWorld.TriggerManager

  describe "build_trigger/1" do
    test "builds trigger from world location data" do
      world_location = %{
        "ID" => 50231,
        "worldId" => 1634,
        "worldZoneId" => 4844,
        "position0" => 4088.0,
        "position1" => -7.5,
        "position2" => -3.6,
        "radius" => 5.0
      }

      trigger = TriggerManager.build_trigger(world_location)

      assert trigger.id == 50231
      assert trigger.world_id == 1634
      assert trigger.zone_id == 4844
      assert trigger.position == {4088.0, -7.5, -3.6}
      assert trigger.radius == 5.0
    end

    test "uses default radius of 3.0 when radius is 0 or 1" do
      world_location = %{
        "ID" => 100,
        "worldId" => 426,
        "worldZoneId" => 1,
        "position0" => 0.0,
        "position1" => 0.0,
        "position2" => 0.0,
        "radius" => 1.0
      }

      trigger = TriggerManager.build_trigger(world_location)
      assert trigger.radius == 3.0
    end
  end

  describe "in_trigger?/2" do
    test "returns true when position is within trigger radius" do
      trigger = %{
        id: 1,
        position: {100.0, 50.0, 200.0},
        radius: 10.0
      }

      assert TriggerManager.in_trigger?({100.0, 50.0, 200.0}, trigger) == true
      assert TriggerManager.in_trigger?({105.0, 50.0, 200.0}, trigger) == true
      assert TriggerManager.in_trigger?({100.0, 55.0, 205.0}, trigger) == true
    end

    test "returns false when position is outside trigger radius" do
      trigger = %{
        id: 1,
        position: {100.0, 50.0, 200.0},
        radius: 10.0
      }

      assert TriggerManager.in_trigger?({200.0, 50.0, 200.0}, trigger) == false
      assert TriggerManager.in_trigger?({100.0, 100.0, 200.0}, trigger) == false
    end
  end

  describe "check_triggers/4" do
    test "returns list of newly entered trigger IDs" do
      triggers = [
        %{id: 1, position: {0.0, 0.0, 0.0}, radius: 10.0},
        %{id: 2, position: {100.0, 0.0, 0.0}, radius: 10.0},
        %{id: 3, position: {200.0, 0.0, 0.0}, radius: 10.0}
      ]

      # Move from outside to inside trigger 1
      old_position = {-50.0, 0.0, 0.0}
      new_position = {0.0, 0.0, 0.0}
      active_triggers = MapSet.new()

      {entered, _exited, _new_active} =
        TriggerManager.check_triggers(triggers, old_position, new_position, active_triggers)

      assert entered == [1]
    end

    test "tracks trigger exit" do
      triggers = [
        %{id: 1, position: {0.0, 0.0, 0.0}, radius: 10.0}
      ]

      # Move from inside to outside trigger 1
      old_position = {0.0, 0.0, 0.0}
      new_position = {50.0, 0.0, 0.0}
      active_triggers = MapSet.new([1])

      {_entered, exited, _new_active} =
        TriggerManager.check_triggers(triggers, old_position, new_position, active_triggers)

      assert exited == [1]
    end

    test "does not re-fire for triggers player is already in" do
      triggers = [
        %{id: 1, position: {0.0, 0.0, 0.0}, radius: 10.0}
      ]

      # Move within trigger 1
      old_position = {0.0, 0.0, 0.0}
      new_position = {5.0, 0.0, 0.0}
      active_triggers = MapSet.new([1])

      {entered, exited, _new_active} =
        TriggerManager.check_triggers(triggers, old_position, new_position, active_triggers)

      assert entered == []
      assert exited == []
    end
  end
end
```

**Verify:** `mix test apps/bezgelor_world/test/trigger_manager_test.exs` - expect compilation error

---

### Task 2: Create TriggerManager module

**File:** `apps/bezgelor_world/lib/bezgelor_world/trigger_manager.ex`

```elixir
defmodule BezgelorWorld.TriggerManager do
  @moduledoc """
  Manages trigger volumes and detects when entities enter/exit them.

  ## Overview

  Trigger volumes are defined by world locations with a position and radius.
  When a player's position update moves them into a trigger, an event is fired.

  ## Usage

      # Load triggers for a zone
      triggers = TriggerManager.load_zone_triggers(zone_id)

      # Check for trigger entry on movement
      {entered, exited, new_active} = TriggerManager.check_triggers(
        triggers,
        old_position,
        new_position,
        active_triggers
      )

      # Fire events for entered triggers
      for trigger_id <- entered do
        EventDispatcher.dispatch_enter_area(session_data, trigger_id, zone_id)
      end
  """

  require Logger

  @type position :: {float(), float(), float()}
  @type trigger :: %{
          id: non_neg_integer(),
          world_id: non_neg_integer(),
          zone_id: non_neg_integer(),
          position: position(),
          radius: float()
        }

  # Default radius for triggers with radius <= 1.0
  @default_radius 3.0

  @doc """
  Load trigger volumes for a zone from world locations.
  """
  @spec load_zone_triggers(non_neg_integer()) :: [trigger()]
  def load_zone_triggers(zone_id) do
    BezgelorData.world_locations_for_zone(zone_id)
    |> Enum.map(&build_trigger/1)
  end

  @doc """
  Load trigger volumes for a world from world locations.
  """
  @spec load_world_triggers(non_neg_integer()) :: [trigger()]
  def load_world_triggers(world_id) do
    BezgelorData.world_locations_for_world(world_id)
    |> Enum.map(&build_trigger/1)
  end

  @doc """
  Build a trigger struct from world location data.
  """
  @spec build_trigger(map()) :: trigger()
  def build_trigger(world_location) do
    raw_radius = Map.get(world_location, "radius", 1.0)
    # Many world locations have radius 1.0 which is too small
    radius = if raw_radius <= 1.0, do: @default_radius, else: raw_radius

    %{
      id: Map.get(world_location, "ID", 0),
      world_id: Map.get(world_location, "worldId", 0),
      zone_id: Map.get(world_location, "worldZoneId", 0),
      position: {
        Map.get(world_location, "position0", 0.0),
        Map.get(world_location, "position1", 0.0),
        Map.get(world_location, "position2", 0.0)
      },
      radius: radius
    }
  end

  @doc """
  Check if a position is within a trigger's radius.
  """
  @spec in_trigger?(position(), trigger()) :: boolean()
  def in_trigger?({px, py, pz}, %{position: {tx, ty, tz}, radius: radius}) do
    dx = px - tx
    dy = py - ty
    dz = pz - tz
    distance_sq = dx * dx + dy * dy + dz * dz
    distance_sq <= radius * radius
  end

  @doc """
  Check which triggers a position update enters/exits.

  Returns `{entered_ids, exited_ids, new_active_set}`.
  """
  @spec check_triggers([trigger()], position(), position(), MapSet.t()) ::
          {[non_neg_integer()], [non_neg_integer()], MapSet.t()}
  def check_triggers(triggers, _old_position, new_position, active_triggers) do
    # Find all triggers the new position is inside
    current_triggers =
      triggers
      |> Enum.filter(&in_trigger?(new_position, &1))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Calculate entered and exited
    entered = MapSet.difference(current_triggers, active_triggers) |> MapSet.to_list()
    exited = MapSet.difference(active_triggers, current_triggers) |> MapSet.to_list()

    {entered, exited, current_triggers}
  end

  @doc """
  Get a specific trigger by ID from a list.
  """
  @spec get_trigger([trigger()], non_neg_integer()) :: trigger() | nil
  def get_trigger(triggers, id) do
    Enum.find(triggers, &(&1.id == id))
  end
end
```

**Verify:** `mix test apps/bezgelor_world/test/trigger_manager_test.exs` - all tests pass

---

### Task 3: Add trigger state to session_data in MovementHandler

**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/movement_handler.ex`

Add to the `do_process_movement/2` function after updating entity position:

```elixir
  defp do_process_movement(packet, state) do
    entity = state.session_data[:entity]
    character_id = state.session_data[:character_id]

    # Get old position before update
    old_position = if entity, do: entity.position, else: {0.0, 0.0, 0.0}

    # Update entity position in memory
    new_position = ClientMovement.position(packet)
    new_rotation = ClientMovement.rotation(packet)
    updated_entity = Entity.update_position(entity, new_position, new_rotation)

    # Update state
    state = put_in(state.session_data[:entity], updated_entity)

    # Throttle database saves
    state = maybe_save_position(character_id, packet, state)

    # Check trigger volumes
    state = check_trigger_volumes(old_position, new_position, state)

    {:ok, state}
  end

  # Check if player entered any trigger volumes
  defp check_trigger_volumes(old_position, new_position, state) do
    triggers = state.session_data[:zone_triggers] || []
    active_triggers = state.session_data[:active_triggers] || MapSet.new()

    if triggers == [] do
      state
    else
      alias BezgelorWorld.TriggerManager

      {entered, _exited, new_active} =
        TriggerManager.check_triggers(triggers, old_position, new_position, active_triggers)

      state = put_in(state.session_data[:active_triggers], new_active)

      # Fire events for entered triggers
      if entered != [] do
        zone_id = state.session_data[:zone_id] || 0
        fire_trigger_events(entered, zone_id, state)
      else
        state
      end
    end
  end

  defp fire_trigger_events([], _zone_id, state), do: state

  defp fire_trigger_events([trigger_id | rest], zone_id, state) do
    alias BezgelorWorld.EventDispatcher

    Logger.info("Player entered trigger #{trigger_id} in zone #{zone_id}")

    {updated_session, _packets} =
      EventDispatcher.dispatch_enter_area(state.session_data, trigger_id, zone_id)

    state = %{state | session_data: updated_session}
    fire_trigger_events(rest, zone_id, state)
  end
```

**Verify:** `mix compile` - compiles without errors

---

### Task 4: Load triggers when player enters world

**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/world_entry_handler.ex`

Find the handler and add trigger loading after zone entry. First, let me check where world entry is handled.

---

### Task 5: Add integration test for trigger detection

**File:** `apps/bezgelor_world/test/trigger_manager_integration_test.exs`

```elixir
defmodule BezgelorWorld.TriggerManagerIntegrationTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.TriggerManager

  describe "load_zone_triggers/1" do
    test "loads triggers for tutorial zone" do
      # Zone 4844 is the Exile tutorial zone
      triggers = TriggerManager.load_zone_triggers(4844)

      # Should have some triggers (world locations)
      assert is_list(triggers)
      # Triggers should have required fields
      for trigger <- triggers do
        assert Map.has_key?(trigger, :id)
        assert Map.has_key?(trigger, :position)
        assert Map.has_key?(trigger, :radius)
      end
    end
  end

  describe "full trigger flow" do
    test "detects trigger entry and exit" do
      # Create a test trigger
      triggers = [
        %{id: 1, position: {100.0, 0.0, 100.0}, radius: 10.0}
      ]

      # Player starts outside
      active = MapSet.new()
      {entered, exited, active} = TriggerManager.check_triggers(
        triggers, {0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}, active
      )
      assert entered == []
      assert exited == []

      # Player moves into trigger
      {entered, exited, active} = TriggerManager.check_triggers(
        triggers, {0.0, 0.0, 0.0}, {100.0, 0.0, 100.0}, active
      )
      assert entered == [1]
      assert exited == []
      assert MapSet.member?(active, 1)

      # Player moves within trigger (no re-fire)
      {entered, exited, active} = TriggerManager.check_triggers(
        triggers, {100.0, 0.0, 100.0}, {105.0, 0.0, 100.0}, active
      )
      assert entered == []
      assert exited == []

      # Player exits trigger
      {entered, exited, _active} = TriggerManager.check_triggers(
        triggers, {105.0, 0.0, 100.0}, {200.0, 0.0, 200.0}, active
      )
      assert entered == []
      assert exited == [1]
    end
  end
end
```

**Verify:** `mix test apps/bezgelor_world/test/trigger_manager_integration_test.exs` - all tests pass

---

### Task 6: Run all tests and commit

**Commands:**

```bash
# Run trigger tests
mix test apps/bezgelor_world/test/trigger_manager_test.exs apps/bezgelor_world/test/trigger_manager_integration_test.exs

# Run full test suite (teleport + trigger)
mix test apps/bezgelor_world/test/teleport_test.exs apps/bezgelor_world/test/trigger_manager*.exs

# Commit
git add -A
git commit -m "feat: add trigger volume detection system (Phase 2)

- Add BezgelorWorld.TriggerManager for trigger volume handling
- Load world locations as triggers for zones
- Check triggers on movement with entry/exit detection
- Fire :enter_area events via EventDispatcher when triggers entered
- Track active triggers in session to prevent re-firing

Phase 2 of tutorial zone systems implementation.
Ref: docs/plans/2025-12-14-tutorial-zone-systems-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Success Criteria

- [ ] TriggerManager builds triggers from world location data
- [ ] in_trigger? correctly checks distance within radius
- [ ] check_triggers returns entered/exited trigger IDs
- [ ] Triggers only fire once when entered (not continuously)
- [ ] Trigger exit is tracked
- [ ] Integration with MovementHandler compiles
- [ ] All tests pass
- [ ] Code committed

## Next Phase

Phase 3: Quest Integration - Wire trigger events to quest objectives for teleport rewards.
