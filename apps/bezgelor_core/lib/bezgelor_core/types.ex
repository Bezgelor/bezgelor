defmodule BezgelorCore.Types do
  @moduledoc """
  Common types used throughout Bezgelor.

  ## Overview

  This module defines core data structures that represent game concepts:
  - `Vector3` - 3D coordinates for positions and rotations
  - More types will be added as needed
  """
end

defmodule BezgelorCore.Types.Vector3 do
  @moduledoc """
  A 3D vector representing a position or direction in the game world.

  ## Fields

  - `x` - X coordinate (east/west)
  - `y` - Y coordinate (up/down, height)
  - `z` - Z coordinate (north/south)

  ## Example

      iex> vec = %BezgelorCore.Types.Vector3{x: 100.0, y: 50.0, z: 200.0}
      iex> vec.x
      100.0
  """

  @type t :: %__MODULE__{
          x: float(),
          y: float(),
          z: float()
        }

  defstruct x: 0.0, y: 0.0, z: 0.0

  @doc """
  Calculate the Euclidean distance between two vectors.

  ## Example

      iex> v1 = %BezgelorCore.Types.Vector3{x: 0.0, y: 0.0, z: 0.0}
      iex> v2 = %BezgelorCore.Types.Vector3{x: 3.0, y: 4.0, z: 0.0}
      iex> BezgelorCore.Types.Vector3.distance(v1, v2)
      5.0
  """
  @spec distance(t(), t()) :: float()
  def distance(%__MODULE__{} = v1, %__MODULE__{} = v2) do
    dx = v2.x - v1.x
    dy = v2.y - v1.y
    dz = v2.z - v1.z
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  @doc """
  Calculate 2D distance (ignoring Y/height).
  """
  @spec distance_2d(t(), t()) :: float()
  def distance_2d(%__MODULE__{} = v1, %__MODULE__{} = v2) do
    dx = v2.x - v1.x
    dz = v2.z - v1.z
    :math.sqrt(dx * dx + dz * dz)
  end

  @doc """
  Get a point at a given angle and distance from this vector (2D, on XZ plane).

  ## Parameters
    - `v` - Starting position
    - `angle` - Angle in radians
    - `distance` - Distance from origin

  ## Example

      iex> v = %BezgelorCore.Types.Vector3{x: 0.0, y: 0.0, z: 0.0}
      iex> result = BezgelorCore.Types.Vector3.get_point_2d(v, 0.0, 5.0)
      iex> Float.round(result.x, 1)
      5.0
  """
  @spec get_point_2d(t(), float(), float()) :: t()
  def get_point_2d(%__MODULE__{} = v, angle, dist) do
    %__MODULE__{
      x: v.x + :math.cos(angle) * dist,
      y: v.y,
      z: v.z + :math.sin(angle) * dist
    }
  end

  @doc """
  Get a random point within a given range (2D, on XZ plane).

  ## Parameters
    - `v` - Center position
    - `max_range` - Maximum distance from center

  ## Example

      iex> v = %BezgelorCore.Types.Vector3{x: 100.0, y: 0.0, z: 100.0}
      iex> result = BezgelorCore.Types.Vector3.get_random_point_2d(v, 10.0)
      iex> BezgelorCore.Types.Vector3.distance_2d(v, result) <= 10.0
      true
  """
  @spec get_random_point_2d(t(), float()) :: t()
  def get_random_point_2d(%__MODULE__{} = v, max_range) do
    angle = :rand.uniform() * 2 * :math.pi()
    dist = :rand.uniform() * max_range
    get_point_2d(v, angle, dist)
  end

  @doc """
  Calculate angle from one vector to another (on XZ plane).

  ## Returns
  Angle in radians.
  """
  @spec angle_to(t(), t()) :: float()
  def angle_to(%__MODULE__{} = from, %__MODULE__{} = to) do
    :math.atan2(to.z - from.z, to.x - from.x)
  end

  @doc """
  Convert from tuple position format {x, y, z} to Vector3.
  """
  @spec from_tuple({float(), float(), float()}) :: t()
  def from_tuple({x, y, z}), do: %__MODULE__{x: x, y: y, z: z}

  @doc """
  Convert to tuple position format {x, y, z}.
  """
  @spec to_tuple(t()) :: {float(), float(), float()}
  def to_tuple(%__MODULE__{x: x, y: y, z: z}), do: {x, y, z}

  @doc """
  Add two vectors.
  """
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{} = v1, %__MODULE__{} = v2) do
    %__MODULE__{
      x: v1.x + v2.x,
      y: v1.y + v2.y,
      z: v1.z + v2.z
    }
  end

  @doc """
  Subtract v2 from v1.
  """
  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{} = v1, %__MODULE__{} = v2) do
    %__MODULE__{
      x: v1.x - v2.x,
      y: v1.y - v2.y,
      z: v1.z - v2.z
    }
  end

  @doc """
  Multiply vector by scalar.
  """
  @spec multiply(t(), float()) :: t()
  def multiply(%__MODULE__{} = v, scalar) do
    %__MODULE__{
      x: v.x * scalar,
      y: v.y * scalar,
      z: v.z * scalar
    }
  end

  @doc """
  Normalize vector to unit length.
  """
  @spec normalize(t()) :: t()
  def normalize(%__MODULE__{} = v) do
    len = :math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)

    if len == 0.0 do
      v
    else
      %__MODULE__{x: v.x / len, y: v.y / len, z: v.z / len}
    end
  end
end
