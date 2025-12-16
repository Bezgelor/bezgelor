defmodule BezgelorCore.Telegraph do
  @moduledoc """
  Telegraph shape-based hit detection for WildStar spells.

  ## Overview

  WildStar uses "telegraphs" - visible ground indicators showing where abilities will hit.
  This module implements the geometry calculations to determine if a target is inside
  a telegraph's area of effect.

  ## Damage Shapes

  | Shape | Enum | Description | Params |
  |-------|------|-------------|--------|
  | Circle | 0 | Area around a point | radius |
  | Ring | 1 | Donut shape | inner_radius, outer_radius |
  | Square | 2 | Square centered on caster | width, height, length |
  | Cone | 4 | Wedge in front of caster | start_radius, end_radius, angle |
  | Pie | 5 | Circle with missing slice | inner_radius, radius, slice_angle |
  | Rectangle | 7 | Rectangle from caster forward | width, height, length |
  | LongCone | 8 | Extended cone | same as Cone |

  ## Usage

      # Create telegraph from data
      telegraph = Telegraph.new(telegraph_data, caster_pos, caster_rotation)

      # Check if target is inside
      Telegraph.inside?(telegraph, target_pos, target_hit_radius)

      # Get search radius for spatial queries
      radius = Telegraph.search_radius(telegraph)
  """

  alias BezgelorCore.Types.Vector3

  # Damage shape enum values (from DamageShape.cs)
  @shape_circle 0
  @shape_ring 1
  @shape_square 2
  @shape_cone 4
  @shape_pie 5
  @shape_rectangle 7
  @shape_long_cone 8

  defstruct [
    :shape,
    :position,
    :rotation,
    :caster_hit_radius,
    # Shape parameters (meaning varies by shape)
    :param00,
    :param01,
    :param02,
    :param03,
    :param04,
    :param05,
    # Timing
    :time_start_ms,
    :time_end_ms,
    # Original data for reference
    :telegraph_data
  ]

  @type t :: %__MODULE__{
          shape: non_neg_integer(),
          position: Vector3.t(),
          rotation: Vector3.t(),
          caster_hit_radius: float(),
          param00: float(),
          param01: float(),
          param02: float(),
          param03: float(),
          param04: float(),
          param05: float(),
          time_start_ms: non_neg_integer(),
          time_end_ms: non_neg_integer(),
          telegraph_data: map()
        }

  @doc """
  Create a new Telegraph from telegraph damage data.

  ## Parameters
    - `telegraph_data` - Map from telegraph_damage.json with shape params
    - `caster_position` - Caster's world position as Vector3 or {x, y, z}
    - `caster_rotation` - Caster's rotation as Vector3 or {rx, ry, rz}
    - `caster_hit_radius` - Caster's hit radius (default 1.0)

  ## Returns
  A Telegraph struct with calculated position/rotation including offsets.
  """
  @spec new(map(), Vector3.t() | {float(), float(), float()}, Vector3.t() | {float(), float(), float()}, float()) :: t()
  def new(telegraph_data, caster_position, caster_rotation, caster_hit_radius \\ 1.0)

  def new(telegraph_data, {cx, cy, cz}, rotation, caster_hit_radius) do
    new(telegraph_data, %Vector3{x: cx, y: cy, z: cz}, rotation, caster_hit_radius)
  end

  def new(telegraph_data, position, {rx, ry, rz}, caster_hit_radius) do
    new(telegraph_data, position, %Vector3{x: rx, y: ry, z: rz}, caster_hit_radius)
  end

  def new(telegraph_data, %Vector3{} = caster_position, %Vector3{} = caster_rotation, caster_hit_radius) do
    telegraph = %__MODULE__{
      shape: Map.get(telegraph_data, :damageShapeEnum, 0),
      position: caster_position,
      rotation: caster_rotation,
      caster_hit_radius: caster_hit_radius,
      param00: Map.get(telegraph_data, :param00, 0.0),
      param01: Map.get(telegraph_data, :param01, 0.0),
      param02: Map.get(telegraph_data, :param02, 0.0),
      param03: Map.get(telegraph_data, :param03, 0.0),
      param04: Map.get(telegraph_data, :param04, 0.0),
      param05: Map.get(telegraph_data, :param05, 0.0),
      time_start_ms: Map.get(telegraph_data, :telegraphTimeStartMs, 0),
      time_end_ms: Map.get(telegraph_data, :telegraphTimeEndMs, 0),
      telegraph_data: telegraph_data
    }

    telegraph
    |> apply_position_offsets(telegraph_data)
    |> apply_rotation_offsets(telegraph_data)
  end

  @doc """
  Check if a target position is inside the telegraph area.

  ## Parameters
    - `telegraph` - The Telegraph struct
    - `target_position` - Target's world position as Vector3 or {x, y, z}
    - `hit_radius` - Target's hit radius (default 1.0)

  ## Returns
  `true` if target is inside the telegraph, `false` otherwise.
  """
  @spec inside?(t(), Vector3.t() | {float(), float(), float()}, float()) :: boolean()
  def inside?(telegraph, {tx, ty, tz}, hit_radius) do
    inside?(telegraph, %Vector3{x: tx, y: ty, z: tz}, hit_radius)
  end

  def inside?(%__MODULE__{shape: @shape_circle} = telegraph, %Vector3{} = target, hit_radius) do
    check_circle(telegraph, target, hit_radius)
  end

  def inside?(%__MODULE__{shape: @shape_ring} = telegraph, %Vector3{} = target, hit_radius) do
    check_ring(telegraph, target, hit_radius)
  end

  def inside?(%__MODULE__{shape: @shape_square} = telegraph, %Vector3{} = target, hit_radius) do
    check_square(telegraph, target, hit_radius)
  end

  def inside?(%__MODULE__{shape: @shape_cone} = telegraph, %Vector3{} = target, hit_radius) do
    check_cone(telegraph, target, hit_radius)
  end

  def inside?(%__MODULE__{shape: @shape_long_cone} = telegraph, %Vector3{} = target, hit_radius) do
    check_cone(telegraph, target, hit_radius)
  end

  def inside?(%__MODULE__{shape: @shape_pie} = telegraph, %Vector3{} = target, hit_radius) do
    check_pie(telegraph, target, hit_radius)
  end

  def inside?(%__MODULE__{shape: @shape_rectangle} = telegraph, %Vector3{} = target, hit_radius) do
    check_rectangle(telegraph, target, hit_radius)
  end

  def inside?(%__MODULE__{shape: shape}, _target, _hit_radius) do
    require Logger
    Logger.warning("Unhandled telegraph shape: #{shape}")
    false
  end

  @doc """
  Get the search radius for spatial queries.

  This is the maximum distance from the telegraph center where targets could
  potentially be hit. Used to optimize entity lookups.
  """
  @spec search_radius(t()) :: float()
  def search_radius(%__MODULE__{shape: @shape_circle, param00: radius}), do: radius
  def search_radius(%__MODULE__{shape: @shape_ring, param01: outer_radius}), do: outer_radius
  def search_radius(%__MODULE__{shape: @shape_cone, param01: radius}), do: radius
  def search_radius(%__MODULE__{shape: @shape_long_cone, param01: radius}), do: radius
  def search_radius(%__MODULE__{shape: @shape_square, param02: length}), do: length
  def search_radius(%__MODULE__{shape: @shape_rectangle, param02: length}), do: length
  def search_radius(%__MODULE__{shape: @shape_pie, param01: radius}), do: radius
  def search_radius(%__MODULE__{}), do: 30.0  # Default fallback

  @doc """
  Get the shape type name as an atom for debugging/logging.
  """
  @spec shape_name(t() | non_neg_integer()) :: atom()
  def shape_name(%__MODULE__{shape: shape}), do: shape_name(shape)
  def shape_name(@shape_circle), do: :circle
  def shape_name(@shape_ring), do: :ring
  def shape_name(@shape_square), do: :square
  def shape_name(@shape_cone), do: :cone
  def shape_name(@shape_pie), do: :pie
  def shape_name(@shape_rectangle), do: :rectangle
  def shape_name(@shape_long_cone), do: :long_cone
  def shape_name(_), do: :unknown

  # Private - Apply position offsets from telegraph data
  defp apply_position_offsets(telegraph, data) do
    x_offset = Map.get(data, :xPositionOffset, 0.0)
    y_offset = Map.get(data, :yPositionOffset, 0.0)
    z_offset = Map.get(data, :zPositionOffset, 0.0)

    if x_offset == 0.0 and y_offset == 0.0 and z_offset == 0.0 do
      telegraph
    else
      # Apply Z offset (forward from caster facing)
      pos =
        if z_offset != 0.0 do
          get_point_for_telegraph(telegraph.position, telegraph.rotation.x + :math.pi() / 2, z_offset)
        else
          telegraph.position
        end

      # Apply Y offset (vertical)
      pos = %Vector3{pos | y: pos.y + y_offset}

      # Apply X offset (sideways from caster facing)
      pos =
        if x_offset != 0.0 do
          get_point_for_telegraph(pos, telegraph.rotation.x + :math.pi(), x_offset)
        else
          pos
        end

      %{telegraph | position: pos}
    end
  end

  # Private - Apply rotation offsets from telegraph data
  defp apply_rotation_offsets(telegraph, data) do
    rotation_degrees = Map.get(data, :rotationDegrees, 0.0)

    if rotation_degrees == 0.0 do
      telegraph
    else
      rotation_radians = telegraph.rotation.x + degrees_to_radians(rotation_degrees)

      # Normalize to -PI to PI range
      rotation_radians = normalize_rotation(rotation_radians)

      %{telegraph | rotation: %Vector3{telegraph.rotation | x: rotation_radians}}
    end
  end

  # Shape check implementations

  defp check_circle(%__MODULE__{position: pos, param00: radius}, %Vector3{} = target, hit_radius) do
    distance_2d(pos, target) <= radius + hit_radius * 0.5
  end

  defp check_ring(%__MODULE__{position: pos, param00: inner_radius, param01: outer_radius}, %Vector3{} = target, hit_radius) do
    dist = distance_2d(pos, target)
    adjusted_hit = hit_radius * 0.5
    dist >= inner_radius - adjusted_hit and dist <= outer_radius + adjusted_hit
  end

  defp check_cone(%__MODULE__{} = telegraph, %Vector3{} = target, hit_radius) do
    caster_hr = telegraph.caster_hit_radius * 0.5
    start_radius = telegraph.param00 - caster_hr
    end_radius = telegraph.param01 + caster_hr
    angle_degrees = telegraph.param02 + telegraph.param00 / 2.0

    check_angle_hit(telegraph, target, hit_radius * 0.5, start_radius, end_radius, angle_degrees)
  end

  defp check_pie(%__MODULE__{} = telegraph, %Vector3{} = target, hit_radius) do
    radius = telegraph.param01
    angle_degrees = telegraph.param02

    # Check if within radius
    distance = distance_3d(telegraph.position, target) - hit_radius * 0.5
    if distance > radius do
      false
    else
      # Pie hits if NOT inside the angle (it's a circle with a missing slice)
      not check_angle_hit(telegraph, target, hit_radius * 0.5, 0.0, radius, angle_degrees)
    end
  end

  defp check_square(%__MODULE__{} = telegraph, %Vector3{} = target, hit_radius) do
    check_rectangular(telegraph, target, hit_radius, :square)
  end

  defp check_rectangle(%__MODULE__{} = telegraph, %Vector3{} = target, hit_radius) do
    check_rectangular(telegraph, target, hit_radius, :rectangle)
  end

  defp check_rectangular(%__MODULE__{} = telegraph, %Vector3{} = target, hit_radius, shape_type) do
    width = telegraph.param00
    height = telegraph.param01
    length = telegraph.param02

    # Height check
    if target.y >= telegraph.position.y + height or target.y <= telegraph.position.y - height do
      false
    else
      # Build the rectangle corners in local space
      {bottom_left, bottom_right, top_left, top_right} =
        if shape_type == :rectangle do
          # Rectangle origin is at base (not centered)
          {
            %Vector3{x: width, y: 0.0, z: 0.0},
            %Vector3{x: -width, y: 0.0, z: 0.0},
            %Vector3{x: width, y: 0.0, z: length},
            %Vector3{x: -width, y: 0.0, z: length}
          }
        else
          # Square is centered
          {
            %Vector3{x: width, y: 0.0, z: -length},
            %Vector3{x: -width, y: 0.0, z: -length},
            %Vector3{x: width, y: 0.0, z: length},
            %Vector3{x: -width, y: 0.0, z: length}
          }
        end

      rotation = telegraph.rotation.x
      pos = telegraph.position

      # Rotate and translate to world space
      bl = Vector3.add(rotate_point_2d(bottom_left, rotation), pos)
      br = Vector3.add(rotate_point_2d(bottom_right, rotation), pos)
      tl = Vector3.add(rotate_point_2d(top_left, rotation), pos)
      tr = Vector3.add(rotate_point_2d(top_right, rotation), pos)

      polygon = [bl, tl, tr, br]

      point_in_polygon?(polygon, target) or radius_intersects_polygon?(polygon, target, hit_radius * 0.5)
    end
  end

  # Check if target is within angle-based shape (cone, pie slice)
  defp check_angle_hit(telegraph, target, hit_radius, start_radius, end_radius, angle_degrees) do
    distance = distance_3d(telegraph.position, target)

    # Check distance bounds
    if distance - hit_radius > end_radius or distance + hit_radius < start_radius do
      false
    else
      # Calculate angle from telegraph position to target
      angle_radians = angle_to(telegraph.position, target) - telegraph.rotation.x
      angle_radians = normalize_rotation(angle_radians)

      angle_deg = abs(radians_to_degrees(angle_radians))
      half_angle = angle_degrees / 2.0

      if angle_deg <= half_angle do
        true
      else
        # Slightly outside angle, but hit radius might clip the edge
        angle_deg <= angle_degrees
      end
    end
  end

  # Math helpers

  defp distance_2d(%Vector3{x: x1, z: z1}, %Vector3{x: x2, z: z2}) do
    dx = x2 - x1
    dz = z2 - z1
    :math.sqrt(dx * dx + dz * dz)
  end

  defp distance_3d(%Vector3{} = v1, %Vector3{} = v2) do
    Vector3.distance(v1, v2)
  end

  defp angle_to(%Vector3{} = from, %Vector3{} = to) do
    Vector3.angle_to(from, to)
  end

  defp get_point_for_telegraph(%Vector3{} = origin, angle, distance) do
    Vector3.get_point_2d(origin, angle, distance)
  end

  defp rotate_point_2d(%Vector3{x: x, y: y, z: z}, rotation) do
    new_x = x * :math.cos(rotation) + z * :math.sin(rotation)
    new_z = -x * :math.sin(rotation) + z * :math.cos(rotation)
    %Vector3{x: -new_x, y: y, z: -new_z}
  end

  defp degrees_to_radians(degrees), do: degrees * :math.pi() / 180.0
  defp radians_to_degrees(radians), do: radians * 180.0 / :math.pi()

  defp normalize_rotation(radians) do
    cond do
      radians > :math.pi() -> radians - 2 * :math.pi()
      radians <= -:math.pi() -> radians + 2 * :math.pi()
      true -> radians
    end
  end

  # Point-in-polygon test using ray casting algorithm
  defp point_in_polygon?(polygon, %Vector3{x: px, z: pz}) do
    n = length(polygon)

    polygon
    |> Enum.with_index()
    |> Enum.reduce(false, fn {%Vector3{x: cx, z: cz}, i}, inside ->
      j = if i == 0, do: n - 1, else: i - 1
      %Vector3{x: nx, z: nz} = Enum.at(polygon, j)

      if ((cz > pz) != (nz > pz)) and (px < (nx - cx) * (pz - cz) / (nz - cz) + cx) do
        not inside
      else
        inside
      end
    end)
  end

  # Check if circle intersects any edge of polygon
  defp radius_intersects_polygon?(polygon, %Vector3{} = center, radius) do
    n = length(polygon)

    Enum.any?(0..(n - 1), fn i ->
      j = rem(i + 1, n)
      line_start = Enum.at(polygon, i)
      line_end = Enum.at(polygon, j)
      line_circle_intersects?(line_start, line_end, center, radius)
    end)
  end

  defp line_circle_intersects?(%Vector3{} = start_p, %Vector3{} = end_p, %Vector3{} = circle, radius) do
    # Check if endpoints are inside circle
    if distance_2d(start_p, circle) < radius or distance_2d(end_p, circle) < radius do
      true
    else
      # Find closest point on line to circle
      closest = closest_point_on_line(start_p, end_p, circle)

      # Check if closest point is on the line segment and within radius
      if point_on_line_segment?(start_p, end_p, closest) do
        distance_2d(closest, circle) <= radius
      else
        false
      end
    end
  end

  defp closest_point_on_line(%Vector3{x: x1, z: z1}, %Vector3{x: x2, z: z2}, %Vector3{x: cx, z: cz}) do
    dx = x2 - x1
    dz = z2 - z1
    len_sq = dx * dx + dz * dz

    if len_sq == 0 do
      %Vector3{x: x1, y: 0.0, z: z1}
    else
      t = ((cx - x1) * dx + (cz - z1) * dz) / len_sq
      t = max(0.0, min(1.0, t))
      %Vector3{x: x1 + t * dx, y: 0.0, z: z1 + t * dz}
    end
  end

  defp point_on_line_segment?(%Vector3{x: x1, z: z1}, %Vector3{x: x2, z: z2}, %Vector3{x: px, z: pz}) do
    d1 = :math.sqrt(:math.pow(px - x1, 2) + :math.pow(pz - z1, 2))
    d2 = :math.sqrt(:math.pow(px - x2, 2) + :math.pow(pz - z2, 2))
    line_len = :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(z2 - z1, 2))

    # Allow small buffer for floating point
    buffer = 0.1
    d1 + d2 >= line_len - buffer and d1 + d2 <= line_len + buffer
  end
end
