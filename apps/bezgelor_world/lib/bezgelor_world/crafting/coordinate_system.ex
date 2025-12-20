defmodule BezgelorWorld.Crafting.CoordinateSystem do
  @moduledoc """
  Coordinate-based crafting system for WildStar tradeskills.

  Handles the 2D grid system where additives shift a cursor position,
  and the final position determines the craft outcome.

  ## Design Note

  Hit detection uses rectangle-based checks rather than complex polygon
  math. This may differ from the original WildStar implementation but
  provides equivalent gameplay with simpler logic.
  """

  @type cursor :: {float(), float()}
  @type zone :: %{
          id: integer(),
          x_min: number(),
          x_max: number(),
          y_min: number(),
          y_max: number(),
          variant_id: integer(),
          quality: atom()
        }
  @type additive :: %{vector_x: float(), vector_y: float()}

  @doc """
  Find which target zone contains the cursor position.

  Returns `{:ok, zone}` if cursor is within a zone, or `:no_zone` if
  the cursor is outside all zones (craft failure).
  """
  @spec find_target_zone(float(), float(), [zone()]) :: {:ok, zone()} | :no_zone
  def find_target_zone(cursor_x, cursor_y, zones) do
    case Enum.find(zones, fn zone ->
           cursor_x >= zone.x_min and cursor_x <= zone.x_max and
             cursor_y >= zone.y_min and cursor_y <= zone.y_max
         end) do
      nil -> :no_zone
      zone -> {:ok, zone}
    end
  end

  @doc """
  Apply an additive to the cursor, optionally with overcharge amplification.
  """
  @spec apply_additive(cursor(), additive(), non_neg_integer()) :: cursor()
  def apply_additive({cursor_x, cursor_y}, additive, overcharge_level) do
    multiplier = calculate_overcharge_multiplier(overcharge_level)

    new_x = cursor_x + additive.vector_x * multiplier
    new_y = cursor_y + additive.vector_y * multiplier

    {new_x, new_y}
  end

  @doc """
  Calculate the vector multiplier for a given overcharge level.

  - Level 0: 1.0x (no amplification)
  - Level 1: 1.25x
  - Level 2: 1.5x
  - Level 3: 2.0x
  """
  @spec calculate_overcharge_multiplier(non_neg_integer()) :: float()
  def calculate_overcharge_multiplier(0), do: 1.0
  def calculate_overcharge_multiplier(1), do: 1.25
  def calculate_overcharge_multiplier(2), do: 1.5
  def calculate_overcharge_multiplier(3), do: 2.0
  # Cap at level 3
  def calculate_overcharge_multiplier(_), do: 2.0

  @doc """
  Calculate the failure chance for a given overcharge level.

  - Level 0: 0% (no risk)
  - Level 1: 10%
  - Level 2: 25%
  - Level 3: 50%
  """
  @spec calculate_failure_chance(non_neg_integer()) :: float()
  def calculate_failure_chance(0), do: 0.0
  def calculate_failure_chance(1), do: 0.10
  def calculate_failure_chance(2), do: 0.25
  def calculate_failure_chance(3), do: 0.50
  # Cap at level 3
  def calculate_failure_chance(_), do: 0.50

  @doc """
  Check if craft failed due to overcharge.
  """
  @spec overcharge_failed?(non_neg_integer()) :: boolean()
  def overcharge_failed?(overcharge_level) do
    failure_chance = calculate_failure_chance(overcharge_level)
    :rand.uniform() < failure_chance
  end

  @doc """
  Clamp cursor position to grid bounds.
  """
  @spec clamp_to_grid(cursor(), number(), number()) :: cursor()
  def clamp_to_grid({x, y}, grid_width, grid_height) do
    clamped_x = x |> max(0) |> min(grid_width)
    clamped_y = y |> max(0) |> min(grid_height)
    {clamped_x, clamped_y}
  end
end
