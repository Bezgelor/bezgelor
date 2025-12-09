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
end
