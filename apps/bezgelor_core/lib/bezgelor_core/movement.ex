defmodule BezgelorCore.Movement do
  @moduledoc """
  Movement generation and path calculation for entities.

  ## Overview

  This module provides movement generators that calculate waypoint paths:

  - `DirectMovementGenerator` - Straight-line path from A to B
  - `RandomMovementGenerator` - Random wandering within a leash radius

  Generators produce lists of waypoints that can be sent to clients
  via ServerEntityCommand packets.

  ## Usage

      # Direct movement to a target
      path = Movement.direct_path(current_pos, target_pos)

      # Random wander from current position
      path = Movement.random_path(current_pos, leash_pos, wander_range)

  ## Path Format

  Paths are lists of `{x, y, z}` tuples representing waypoints.
  Waypoints are generated at `@step_size` intervals (2.0 units by default).
  """

  alias BezgelorCore.Types.Vector3

  # Distance between waypoints (same as NexusForever)
  @step_size 2.0

  # Spline modes for path playback
  @type spline_mode :: :one_shot | :loop | :back_and_forth

  @type position :: {float(), float(), float()}
  @type path :: [position()]

  @doc """
  Calculate a direct path from start to destination.

  Generates waypoints at 2-unit intervals along a straight line.
  The final waypoint is always the exact destination.

  ## Parameters
    - `start` - Starting position as {x, y, z}
    - `destination` - Target position as {x, y, z}
    - `terrain_fn` - Optional function to get terrain height: fn(x, z) -> y

  ## Returns
  List of waypoint positions [{x, y, z}, ...]

  ## Example

      iex> Movement.direct_path({0.0, 0.0, 0.0}, {10.0, 0.0, 0.0})
      [{0.0, 0.0, 0.0}, {2.0, 0.0, 0.0}, {4.0, 0.0, 0.0}, {6.0, 0.0, 0.0}, {8.0, 0.0, 0.0}, {10.0, 0.0, 0.0}]
  """
  @spec direct_path(position(), position(), (float(), float() -> float()) | nil) :: path()
  def direct_path(start, destination, terrain_fn \\ nil)

  def direct_path({sx, sy, sz} = start, {dx, dy, dz} = destination, terrain_fn) do
    start_vec = %Vector3{x: sx, y: sy, z: sz}
    dest_vec = %Vector3{x: dx, y: dy, z: dz}

    distance = Vector3.distance_2d(start_vec, dest_vec)

    if distance < @step_size do
      # Too close, just return start and destination
      [start, destination]
    else
      angle = Vector3.angle_to(start_vec, dest_vec)
      num_steps = floor(distance / @step_size)

      # Generate intermediate waypoints
      waypoints =
        for i <- 0..(num_steps - 1) do
          point = Vector3.get_point_2d(start_vec, angle, @step_size * i)

          # Apply terrain height if provided
          y =
            if terrain_fn do
              terrain_fn.(point.x, point.z)
            else
              # Interpolate Y between start and dest
              progress = i / num_steps
              sy + (dy - sy) * progress
            end

          {point.x, y, point.z}
        end

      # Always end at exact destination
      waypoints ++ [destination]
    end
  end

  @doc """
  Calculate a random wandering path from current position.

  Picks a random point within `wander_range` of the `leash_position`,
  then generates a direct path to that point.

  ## Parameters
    - `current_pos` - Current entity position
    - `leash_pos` - Center point for wandering (usually spawn position)
    - `wander_range` - Maximum distance from leash center
    - `terrain_fn` - Optional function to get terrain height

  ## Returns
  List of waypoint positions [{x, y, z}, ...]
  """
  @spec random_path(position(), position(), float(), (float(), float() -> float()) | nil) ::
          path()
  def random_path(current_pos, leash_pos, wander_range, terrain_fn \\ nil) do
    {lx, ly, lz} = leash_pos
    leash_vec = %Vector3{x: lx, y: ly, z: lz}

    # Pick random destination within wander range of leash
    dest_vec = Vector3.get_random_point_2d(leash_vec, wander_range)

    # Get terrain height for destination if available
    dest_y =
      if terrain_fn do
        terrain_fn.(dest_vec.x, dest_vec.z)
      else
        ly
      end

    destination = {dest_vec.x, dest_y, dest_vec.z}

    direct_path(current_pos, destination, terrain_fn)
  end

  @doc """
  Calculate path to follow a target entity.

  Calculates position behind the target and generates path to that point.
  Used for pets, companions, and escorting NPCs.

  ## Parameters
    - `current_pos` - Follower's current position
    - `target_pos` - Target entity position
    - `target_rotation` - Target's facing direction (radians)
    - `follow_distance` - How far behind to follow
    - `terrain_fn` - Optional terrain height function

  ## Returns
  List of waypoint positions or empty list if already close enough.
  """
  @spec follow_path(position(), position(), float(), float(), (float(), float() -> float()) | nil) ::
          path()
  def follow_path(current_pos, target_pos, target_rotation, follow_distance, terrain_fn \\ nil) do
    {tx, ty, tz} = target_pos
    target_vec = %Vector3{x: tx, y: ty, z: tz}

    # Calculate position behind target
    # Rotation is facing direction, so we go in opposite direction
    behind_angle = target_rotation + :math.pi()
    dest_vec = Vector3.get_point_2d(target_vec, behind_angle, follow_distance)

    # Get terrain height if available
    dest_y =
      if terrain_fn do
        terrain_fn.(dest_vec.x, dest_vec.z)
      else
        ty
      end

    destination = {dest_vec.x, dest_y, dest_vec.z}

    # Only generate path if we need to move
    {cx, cy, cz} = current_pos
    current_vec = %Vector3{x: cx, y: cy, z: cz}
    dest_check = %Vector3{x: dest_vec.x, y: dest_y, z: dest_vec.z}

    if Vector3.distance_2d(current_vec, dest_check) > @step_size do
      direct_path(current_pos, destination, terrain_fn)
    else
      []
    end
  end

  @doc """
  Calculate the total length of a path.
  """
  @spec path_length(path()) :: float()
  def path_length([]), do: 0.0
  def path_length([_single]), do: 0.0

  def path_length(path) do
    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [{x1, y1, z1}, {x2, y2, z2}], acc ->
      v1 = %Vector3{x: x1, y: y1, z: z1}
      v2 = %Vector3{x: x2, y: y2, z: z2}
      acc + Vector3.distance(v1, v2)
    end)
  end

  @doc """
  Calculate travel time for a path at a given speed.

  ## Parameters
    - `path` - List of waypoints
    - `speed` - Movement speed in units per second

  ## Returns
  Time in milliseconds to traverse the path.
  """
  @spec path_duration(path(), float()) :: non_neg_integer()
  def path_duration(path, speed) when speed > 0 do
    length = path_length(path)
    round(length / speed * 1000)
  end

  def path_duration(_path, _speed), do: 0

  @doc """
  Get position along a path at a given progress.

  ## Parameters
    - `path` - List of waypoints
    - `progress` - Progress along path (0.0 to 1.0)

  ## Returns
  Interpolated position at the given progress.
  """
  @spec interpolate_path(path(), float()) :: position()
  def interpolate_path([], _progress), do: {0.0, 0.0, 0.0}
  def interpolate_path([single], _progress), do: single
  def interpolate_path(path, progress) when progress <= 0.0, do: hd(path)
  def interpolate_path(path, progress) when progress >= 1.0, do: List.last(path)

  def interpolate_path(path, progress) do
    total_length = path_length(path)
    target_distance = total_length * progress

    find_position_at_distance(path, target_distance, 0.0)
  end

  defp find_position_at_distance([current], _target, _accumulated), do: current

  defp find_position_at_distance(
         [{x1, y1, z1} = _current, {x2, y2, z2} = next | rest],
         target,
         accumulated
       ) do
    v1 = %Vector3{x: x1, y: y1, z: z1}
    v2 = %Vector3{x: x2, y: y2, z: z2}
    segment_length = Vector3.distance(v1, v2)

    if accumulated + segment_length >= target do
      # Target is in this segment
      segment_progress = (target - accumulated) / segment_length
      interpolated = Vector3.add(v1, Vector3.multiply(Vector3.subtract(v2, v1), segment_progress))
      Vector3.to_tuple(interpolated)
    else
      find_position_at_distance([next | rest], target, accumulated + segment_length)
    end
  end

  @doc """
  Generate a chase path toward a target, stopping at attack range.

  ## Parameters

  - `current_pos` - Current position of the chaser
  - `target_pos` - Position of the target
  - `attack_range` - Distance at which to stop (attack range)
  - `opts` - Options:
    - `:step_size` - Distance between waypoints (default 2.0)

  ## Returns

  List of waypoints from current position to attack range distance from target.
  Returns empty list if already in range.
  """
  @spec chase_path(position(), position(), float(), keyword()) :: path()
  def chase_path(current_pos, target_pos, attack_range, opts \\ []) do
    step_size = Keyword.get(opts, :step_size, @step_size)

    {cx, cy, cz} = current_pos
    {tx, ty, tz} = target_pos

    dx = tx - cx
    dy = ty - cy
    dz = tz - cz
    total_distance = :math.sqrt(dx * dx + dy * dy + dz * dz)

    # Already in range
    if total_distance <= attack_range do
      []
    else
      # Calculate stop point (attack_range distance from target)
      stop_distance = total_distance - attack_range

      # Normalize direction
      nx = dx / total_distance
      ny = dy / total_distance
      nz = dz / total_distance

      # Generate waypoints
      num_steps = ceil(stop_distance / step_size)

      0..num_steps
      |> Enum.map(fn step ->
        progress = min(step * step_size / stop_distance, 1.0)

        {
          cx + nx * stop_distance * progress,
          cy + ny * stop_distance * progress,
          cz + nz * stop_distance * progress
        }
      end)
    end
  end

  @doc """
  Generate path for ranged creature to maintain optimal distance.

  Moves to the middle of the min/max range to maintain safe attack distance.
  Will move backward if too close to target, forward if too far.

  ## Parameters

  - `current_pos` - Current position
  - `target_pos` - Target position
  - `min_range` - Minimum safe distance
  - `max_range` - Maximum attack range

  ## Returns

  Path to optimal position (middle of min/max range from target).
  Returns empty list if already in optimal range.
  """
  @spec ranged_position_path(position(), position(), float(), float()) :: path()
  def ranged_position_path(current_pos, target_pos, min_range, max_range) do
    {cx, cy, cz} = current_pos
    {tx, ty, tz} = target_pos

    dx = tx - cx
    dy = ty - cy
    dz = tz - cz
    current_distance = :math.sqrt(dx * dx + dy * dy + dz * dz)

    optimal_distance = (min_range + max_range) / 2

    cond do
      # Already in optimal zone
      current_distance >= min_range and current_distance <= max_range ->
        []

      # Too close - back away from target
      current_distance < min_range ->
        # Normalize direction AWAY from target
        nx = -dx / current_distance
        ny = -dy / current_distance
        nz = -dz / current_distance

        # Move to optimal distance
        move_distance = optimal_distance - current_distance

        generate_path_direction({cx, cy, cz}, {nx, ny, nz}, move_distance)

      # Too far - move closer (use chase_path logic)
      current_distance > max_range ->
        chase_path(current_pos, target_pos, optimal_distance)
    end
  end

  # Generate path in a specific direction for a given distance
  defp generate_path_direction({cx, cy, cz}, {nx, ny, nz}, distance) do
    num_steps = ceil(distance / @step_size)

    0..num_steps
    |> Enum.map(fn step ->
      progress = min(step * @step_size / distance, 1.0)

      {
        cx + nx * distance * progress,
        cy + ny * distance * progress,
        cz + nz * distance * progress
      }
    end)
  end

  @doc """
  Calculate rotation to face a target position.

  Returns rotation in radians (yaw around Y axis).
  Uses atan2(dx, dz) convention where +Z is 0, +X is PI/2.

  ## Parameters

  - `current` - Current position as {x, y, z}
  - `target` - Target position as {x, y, z}

  ## Returns

  Rotation in radians.
  """
  @spec rotation_toward(position(), position()) :: float()
  def rotation_toward({cx, _cy, cz}, {tx, _ty, tz}) do
    dx = tx - cx
    dz = tz - cz
    :math.atan2(dx, dz)
  end

  @doc """
  Check if a position is within leash range of spawn.
  """
  @spec within_leash?(position(), position(), float()) :: boolean()
  def within_leash?({x1, y1, z1}, {x2, y2, z2}, leash_range) do
    v1 = %Vector3{x: x1, y: y1, z: z1}
    v2 = %Vector3{x: x2, y: y2, z: z2}
    Vector3.distance_2d(v1, v2) <= leash_range
  end
end
