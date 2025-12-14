# Phase 1: Core Teleportation Implementation Plan

**Date:** 2025-12-14
**Status:** Ready for Implementation
**Prerequisite:** Design document `docs/plans/2025-12-14-tutorial-zone-systems-design.md`

## Goal

Implement the foundational teleportation system that moves players between world locations. This enables quest-gated zone transitions in future phases.

## Architecture

```
BezgelorWorld.Teleport
├── to_world_location(session, world_location_id)    # Teleport to location by ID
├── to_position(session, world_id, position, rotation)  # Teleport to coordinates
└── Helper functions for validation and packet sending

Flow:
1. Validate world_location exists (BezgelorData.get_world_location/1)
2. Remove entity from current zone (ServerEntityDestroy with :teleport reason)
3. Update session state with new position
4. Send zone transition packets (ServerWorldEnter, ServerEntityCreate)
5. Register entity in destination zone
```

## Tech Stack

- **Module:** `BezgelorWorld.Teleport`
- **Tests:** `apps/bezgelor_world/test/teleport_test.exs`
- **Packets:** Existing `ServerWorldEnter`, `ServerEntityDestroy`, `ServerEntityCreate`
- **Data:** `BezgelorData.get_world_location/1` for destination lookup

## Tasks

### Task 1: Create Teleport test file with basic test structure

**File:** `apps/bezgelor_world/test/teleport_test.exs`

```elixir
defmodule BezgelorWorld.TeleportTest do
  use ExUnit.Case, async: false

  alias BezgelorWorld.Teleport
  alias BezgelorWorld.Zone.InstanceSupervisor
  alias BezgelorCore.Entity

  describe "to_world_location/2" do
    test "returns error for non-existent world location" do
      # World location ID that doesn't exist
      fake_session = %{
        session_data: %{
          player_guid: 1,
          zone_id: 1,
          instance_id: 1
        }
      }

      assert {:error, :invalid_location} = Teleport.to_world_location(fake_session, 999_999_999)
    end
  end

  describe "to_position/4" do
    test "returns error for invalid world_id" do
      fake_session = %{
        session_data: %{
          player_guid: 1,
          zone_id: 1,
          instance_id: 1
        }
      }

      assert {:error, :invalid_world} = Teleport.to_position(fake_session, 0, {0.0, 0.0, 0.0})
    end
  end

  describe "build_spawn_from_world_location/1" do
    test "converts world location data to spawn format" do
      world_location = %{
        "ID" => 100,
        "worldId" => 426,
        "worldZoneId" => 1,
        "position0" => 100.0,
        "position1" => 50.0,
        "position2" => 200.0,
        "facing0" => 0.0,
        "facing1" => 0.0,
        "facing2" => 0.0,
        "facing3" => 1.0
      }

      spawn = Teleport.build_spawn_from_world_location(world_location)

      assert spawn.world_id == 426
      assert spawn.zone_id == 1
      assert spawn.position == {100.0, 50.0, 200.0}
      # Quaternion to euler: facing3=1.0 with others 0 => yaw=0
      assert spawn.rotation == {0.0, 0.0, 0.0}
    end
  end
end
```

**Verify:** `mix test apps/bezgelor_world/test/teleport_test.exs` - expect compilation error (module doesn't exist)

---

### Task 2: Create Teleport module skeleton

**File:** `apps/bezgelor_world/lib/bezgelor_world/teleport.ex`

```elixir
defmodule BezgelorWorld.Teleport do
  @moduledoc """
  Teleportation system for moving players between world locations.

  ## Usage

      # Teleport to a world location by ID
      Teleport.to_world_location(session, world_location_id)

      # Teleport to specific coordinates
      Teleport.to_position(session, world_id, {x, y, z}, {rx, ry, rz})

  ## World Location Data

  World locations are defined in `world_locations.json` with:
  - ID: Unique location identifier
  - worldId: Destination world/map ID
  - worldZoneId: Destination zone ID
  - position0/1/2: X, Y, Z coordinates
  - facing0/1/2/3: Quaternion rotation
  - radius: Trigger radius (used for area detection)
  """

  require Logger

  @type session :: map()
  @type position :: {float(), float(), float()}
  @type rotation :: {float(), float(), float()}
  @type spawn_location :: %{
          world_id: non_neg_integer(),
          zone_id: non_neg_integer(),
          position: position(),
          rotation: rotation()
        }

  @doc """
  Teleport player to a world location by ID.

  Looks up the world location data and teleports the player there.
  """
  @spec to_world_location(session(), non_neg_integer()) ::
          {:ok, session()} | {:error, :invalid_location | :teleport_failed}
  def to_world_location(_session, _world_location_id) do
    {:error, :invalid_location}
  end

  @doc """
  Teleport player to specific world coordinates.

  Used for direct coordinate teleports (e.g., GM commands, respawns).
  """
  @spec to_position(session(), non_neg_integer(), position(), rotation()) ::
          {:ok, session()} | {:error, :invalid_world | :teleport_failed}
  def to_position(_session, world_id, _position, _rotation \\ {0.0, 0.0, 0.0})

  def to_position(_session, 0, _position, _rotation) do
    {:error, :invalid_world}
  end

  def to_position(_session, _world_id, _position, _rotation) do
    {:error, :teleport_failed}
  end

  @doc """
  Convert world location data to spawn location format.

  Takes raw world location data (from JSON) and converts it to the
  spawn_location format used by the zone system.
  """
  @spec build_spawn_from_world_location(map()) :: spawn_location()
  def build_spawn_from_world_location(world_location) do
    # Extract position
    x = Map.get(world_location, "position0", 0.0)
    y = Map.get(world_location, "position1", 0.0)
    z = Map.get(world_location, "position2", 0.0)

    # Extract quaternion and convert to euler angles
    # For now, use simplified conversion (assumes mostly yaw rotation)
    _qx = Map.get(world_location, "facing0", 0.0)
    _qy = Map.get(world_location, "facing1", 0.0)
    qz = Map.get(world_location, "facing2", 0.0)
    qw = Map.get(world_location, "facing3", 1.0)

    # Simplified yaw extraction from quaternion: yaw = 2 * atan2(qz, qw)
    yaw = 2.0 * :math.atan2(qz, qw)

    %{
      world_id: Map.get(world_location, "worldId", 0),
      zone_id: Map.get(world_location, "worldZoneId", 0),
      position: {x, y, z},
      rotation: {0.0, 0.0, yaw}
    }
  end
end
```

**Verify:** `mix test apps/bezgelor_world/test/teleport_test.exs` - tests should run, 2 pass, 1 fail (build_spawn test passes)

---

### Task 3: Implement to_world_location with location lookup

**File:** `apps/bezgelor_world/lib/bezgelor_world/teleport.ex`

Replace the `to_world_location/2` function:

```elixir
  @doc """
  Teleport player to a world location by ID.

  Looks up the world location data and teleports the player there.
  """
  @spec to_world_location(session(), non_neg_integer()) ::
          {:ok, session()} | {:error, :invalid_location | :teleport_failed}
  def to_world_location(session, world_location_id) do
    case BezgelorData.get_world_location(world_location_id) do
      {:ok, world_location} ->
        spawn = build_spawn_from_world_location(world_location)
        to_position(session, spawn.world_id, spawn.position, spawn.rotation)

      :error ->
        Logger.warning("Teleport failed: world location #{world_location_id} not found")
        {:error, :invalid_location}
    end
  end
```

**Verify:** `mix test apps/bezgelor_world/test/teleport_test.exs` - invalid location test still passes

---

### Task 4: Add test for successful position teleport (same zone)

**File:** `apps/bezgelor_world/test/teleport_test.exs`

Add new test in the `describe "to_position/4"` block:

```elixir
    setup do
      # Create a test zone instance
      zone_id = System.unique_integer([:positive])
      instance_id = 1
      world_id = 426

      zone_data = %{id: zone_id, name: "Test Zone"}
      {:ok, _pid} = InstanceSupervisor.start_instance(zone_id, instance_id, zone_data)

      on_exit(fn ->
        InstanceSupervisor.stop_instance(zone_id, instance_id)
      end)

      %{zone_id: zone_id, instance_id: instance_id, world_id: world_id}
    end

    test "teleports player to new position in same zone", %{zone_id: zone_id, instance_id: instance_id, world_id: world_id} do
      player_guid = System.unique_integer([:positive])

      # Add player entity to zone
      player = %Entity{
        guid: player_guid,
        type: :player,
        name: "TestPlayer",
        position: {0.0, 0.0, 0.0}
      }

      BezgelorWorld.Zone.Instance.add_entity({zone_id, instance_id}, player)
      Process.sleep(10)

      session = %{
        session_data: %{
          player_guid: player_guid,
          zone_id: zone_id,
          instance_id: instance_id,
          world_id: world_id,
          character: %{id: 1, name: "TestPlayer"}
        }
      }

      new_position = {100.0, 50.0, 200.0}
      new_rotation = {0.0, 0.0, 1.57}

      assert {:ok, updated_session} = Teleport.to_position(session, world_id, new_position, new_rotation)

      # Verify session was updated
      assert updated_session.session_data.spawn_location.position == new_position
    end
```

**Verify:** `mix test apps/bezgelor_world/test/teleport_test.exs` - new test fails (to_position not implemented)

---

### Task 5: Implement to_position for same-zone teleport

**File:** `apps/bezgelor_world/lib/bezgelor_world/teleport.ex`

Replace the `to_position/4` function:

```elixir
  @doc """
  Teleport player to specific world coordinates.

  Used for direct coordinate teleports (e.g., GM commands, respawns).
  """
  @spec to_position(session(), non_neg_integer(), position(), rotation()) ::
          {:ok, session()} | {:error, :invalid_world | :teleport_failed}
  def to_position(session, world_id, position, rotation \\ {0.0, 0.0, 0.0})

  def to_position(_session, 0, _position, _rotation) do
    {:error, :invalid_world}
  end

  def to_position(session, world_id, position, rotation) do
    current_world_id = get_in(session, [:session_data, :world_id])

    spawn = %{
      world_id: world_id,
      zone_id: get_in(session, [:session_data, :zone_id]) || 1,
      position: position,
      rotation: rotation
    }

    if current_world_id == world_id do
      # Same zone teleport - just update position
      same_zone_teleport(session, spawn)
    else
      # Cross-zone teleport - full zone transition
      cross_zone_teleport(session, spawn)
    end
  end

  # Same-zone teleport: Update entity position, no zone change needed
  defp same_zone_teleport(session, spawn) do
    player_guid = get_in(session, [:session_data, :player_guid])
    zone_id = get_in(session, [:session_data, :zone_id])
    instance_id = get_in(session, [:session_data, :instance_id]) || 1

    # Update entity position in zone
    case BezgelorWorld.Zone.Instance.update_entity_position(
           {zone_id, instance_id},
           player_guid,
           spawn.position
         ) do
      :ok ->
        # Update session with new spawn location
        session = put_in(session, [:session_data, :spawn_location], spawn)
        Logger.info("Same-zone teleport: player #{player_guid} to #{inspect(spawn.position)}")
        {:ok, session}

      :error ->
        Logger.warning("Same-zone teleport failed: entity #{player_guid} not found in zone")
        {:error, :teleport_failed}
    end
  end

  # Cross-zone teleport: Full zone transition with packet sequence
  defp cross_zone_teleport(session, spawn) do
    # For now, just update session - packet sending will be added later
    # when we have proper connection handling
    session = put_in(session, [:session_data, :spawn_location], spawn)
    session = put_in(session, [:session_data, :world_id], spawn.world_id)
    session = put_in(session, [:session_data, :zone_id], spawn.zone_id)

    Logger.info("Cross-zone teleport: to world #{spawn.world_id}, zone #{spawn.zone_id}")
    {:ok, session}
  end
```

**Verify:** `mix test apps/bezgelor_world/test/teleport_test.exs` - all tests pass

---

### Task 6: Add test for cross-zone teleport

**File:** `apps/bezgelor_world/test/teleport_test.exs`

Add to the `describe "to_position/4"` block:

```elixir
    test "teleports player to different zone", %{zone_id: zone_id, instance_id: instance_id} do
      player_guid = System.unique_integer([:positive])

      session = %{
        session_data: %{
          player_guid: player_guid,
          zone_id: zone_id,
          instance_id: instance_id,
          world_id: 426,
          character: %{id: 1, name: "TestPlayer"}
        }
      }

      # Teleport to different world
      new_world_id = 1387
      new_position = {-3835.0, -980.0, -6050.0}

      assert {:ok, updated_session} = Teleport.to_position(session, new_world_id, new_position)

      # Verify session was updated with new world
      assert updated_session.session_data.world_id == new_world_id
      assert updated_session.session_data.spawn_location.world_id == new_world_id
    end
```

**Verify:** `mix test apps/bezgelor_world/test/teleport_test.exs` - all tests pass

---

### Task 7: Create teleport handler for /teleport command

**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/teleport_command_handler.ex`

```elixir
defmodule BezgelorProtocol.Handler.TeleportCommandHandler do
  @moduledoc """
  Handler for /teleport chat command (GM command).

  ## Usage

  In chat:
  - `/teleport <world_location_id>` - Teleport to world location
  - `/teleport <x> <y> <z>` - Teleport to coordinates in current zone
  - `/teleport <world_id> <x> <y> <z>` - Teleport to coordinates in specified world

  ## Examples

      /teleport 50231       # Teleport to Exile tutorial start
      /teleport 100 50 200  # Teleport to x=100, y=50, z=200 in current zone
  """

  alias BezgelorWorld.Teleport

  require Logger

  @doc """
  Parse and execute teleport command.

  Returns {:ok, updated_session} on success, or {:error, reason} on failure.
  """
  @spec handle(String.t(), map()) :: {:ok, map()} | {:error, atom()}
  def handle(args, session) do
    args
    |> String.trim()
    |> String.split(~r/\s+/)
    |> parse_and_execute(session)
  end

  # Single argument: world location ID
  defp parse_and_execute([world_location_id_str], session) do
    case Integer.parse(world_location_id_str) do
      {world_location_id, ""} ->
        Teleport.to_world_location(session, world_location_id)

      _ ->
        {:error, :invalid_arguments}
    end
  end

  # Three arguments: x y z (current zone)
  defp parse_and_execute([x_str, y_str, z_str], session) do
    with {x, ""} <- Float.parse(x_str),
         {y, ""} <- Float.parse(y_str),
         {z, ""} <- Float.parse(z_str) do
      world_id = get_in(session, [:session_data, :world_id]) || 426
      Teleport.to_position(session, world_id, {x, y, z})
    else
      _ -> {:error, :invalid_arguments}
    end
  end

  # Four arguments: world_id x y z
  defp parse_and_execute([world_id_str, x_str, y_str, z_str], session) do
    with {world_id, ""} <- Integer.parse(world_id_str),
         {x, ""} <- Float.parse(x_str),
         {y, ""} <- Float.parse(y_str),
         {z, ""} <- Float.parse(z_str) do
      Teleport.to_position(session, world_id, {x, y, z})
    else
      _ -> {:error, :invalid_arguments}
    end
  end

  defp parse_and_execute(_, _session) do
    {:error, :invalid_arguments}
  end
end
```

**Verify:** `mix compile` - compiles without errors

---

### Task 8: Add teleport command handler test

**File:** `apps/bezgelor_protocol/test/handler/teleport_command_handler_test.exs`

```elixir
defmodule BezgelorProtocol.Handler.TeleportCommandHandlerTest do
  use ExUnit.Case, async: true

  alias BezgelorProtocol.Handler.TeleportCommandHandler

  describe "handle/2" do
    setup do
      session = %{
        session_data: %{
          player_guid: 12345,
          zone_id: 1,
          instance_id: 1,
          world_id: 426,
          character: %{id: 1, name: "TestPlayer"}
        }
      }

      %{session: session}
    end

    test "parses single world location ID argument", %{session: session} do
      # This will fail because location doesn't exist, but parsing works
      assert {:error, :invalid_location} = TeleportCommandHandler.handle("999999999", session)
    end

    test "parses three coordinate arguments", %{session: session} do
      # Should attempt teleport to coordinates
      result = TeleportCommandHandler.handle("100.0 50.0 200.0", session)

      # Will fail because entity not in zone, but parsing succeeded
      assert {:error, :teleport_failed} = result
    end

    test "parses four arguments (world_id + coordinates)", %{session: session} do
      # Cross-zone teleport to new world
      result = TeleportCommandHandler.handle("1387 -3835.0 -980.0 -6050.0", session)

      # Cross-zone just updates session (no entity check)
      assert {:ok, updated_session} = result
      assert updated_session.session_data.world_id == 1387
    end

    test "returns error for invalid arguments", %{session: session} do
      assert {:error, :invalid_arguments} = TeleportCommandHandler.handle("not_a_number", session)
      assert {:error, :invalid_arguments} = TeleportCommandHandler.handle("1 2", session)
      assert {:error, :invalid_arguments} = TeleportCommandHandler.handle("", session)
    end
  end
end
```

**Verify:** `mix test apps/bezgelor_protocol/test/handler/teleport_command_handler_test.exs` - all tests pass

---

### Task 9: Wire teleport command to chat handler

**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/chat_handler.ex`

Add to the imports at the top:

```elixir
alias BezgelorProtocol.Handler.TeleportCommandHandler
```

Find the `handle_command/3` function and add a new clause for `/teleport`:

```elixir
  defp handle_command("teleport", args, state) do
    case TeleportCommandHandler.handle(args, state) do
      {:ok, updated_state} ->
        # TODO: Send position update packets to client
        Logger.info("Teleport successful for player #{state.session_data[:character_name]}")
        {:noreply, updated_state}

      {:error, reason} ->
        Logger.warning("Teleport failed: #{reason}")
        {:noreply, state}
    end
  end
```

**Verify:** `mix compile` - compiles without errors

---

### Task 10: Run full test suite and commit

**Commands:**

```bash
# Run teleport-related tests
mix test apps/bezgelor_world/test/teleport_test.exs apps/bezgelor_protocol/test/handler/teleport_command_handler_test.exs

# Run full test suite
mix test

# If all pass, commit
git add -A
git commit -m "feat: add core teleportation system

- Add BezgelorWorld.Teleport module with to_world_location/2 and to_position/4
- Support same-zone teleports (position update only)
- Support cross-zone teleports (session state update)
- Add /teleport command handler for testing
- Convert world location quaternion to euler angles for rotation

Phase 1 of tutorial zone systems implementation.
Ref: docs/plans/2025-12-14-tutorial-zone-systems-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Success Criteria

- [ ] `BezgelorWorld.Teleport.to_world_location/2` looks up location and teleports
- [ ] `BezgelorWorld.Teleport.to_position/4` handles same-zone and cross-zone teleports
- [ ] World location quaternion rotation converted to euler angles
- [ ] `/teleport` command parses all argument formats
- [ ] All tests pass
- [ ] Code committed

## Next Phase

Phase 2: Trigger Volumes - Detect when players enter trigger areas to fire events.
