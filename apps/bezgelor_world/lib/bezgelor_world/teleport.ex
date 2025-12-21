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

  # Same-zone teleport: Update entity position, no zone change needed
  defp same_zone_teleport(session, spawn) do
    player_guid = get_in(session, [:session_data, :player_guid])
    # World.Instance is keyed by world_id, not zone_id
    world_id = get_in(session, [:session_data, :world_id])
    instance_id = get_in(session, [:session_data, :instance_id]) || 1

    # Update entity position in world instance
    case BezgelorWorld.World.Instance.update_entity_position(
           {world_id, instance_id},
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
end
