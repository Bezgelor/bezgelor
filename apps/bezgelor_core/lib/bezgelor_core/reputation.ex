defmodule BezgelorCore.Reputation do
  @moduledoc """
  Reputation level definitions and calculations.

  ## Levels (from WildStar)

  | Level      | Standing Range  | Vendor Discount |
  |------------|-----------------|-----------------|
  | Hated      | -42000 to -6000 | 0%              |
  | Hostile    | -6000 to -3000  | 0%              |
  | Unfriendly | -3000 to 0      | 0%              |
  | Neutral    | 0 to 3000       | 0%              |
  | Friendly   | 3000 to 9000    | 5%              |
  | Honored    | 9000 to 21000   | 10%             |
  | Revered    | 21000 to 42000  | 15%             |
  | Exalted    | 42000+          | 20%             |
  """

  @levels [
    {:hated, -42000, -6000},
    {:hostile, -6000, -3000},
    {:unfriendly, -3000, 0},
    {:neutral, 0, 3000},
    {:friendly, 3000, 9000},
    {:honored, 9000, 21000},
    {:revered, 21000, 42000},
    {:exalted, 42000, :infinity}
  ]

  @type level ::
          :hated | :hostile | :unfriendly | :neutral | :friendly | :honored | :revered | :exalted

  @doc "Convert raw standing points to a reputation level."
  @spec standing_to_level(integer()) :: level()
  def standing_to_level(standing) do
    Enum.find_value(@levels, :neutral, fn {level, min, max} ->
      if standing >= min and (max == :infinity or standing < max), do: level
    end)
  end

  @doc "Get progress within current reputation level."
  @spec level_progress(integer()) :: {level(), integer(), integer()}
  def level_progress(standing) do
    level = standing_to_level(standing)
    {_level, min, max} = Enum.find(@levels, fn {l, _, _} -> l == level end)

    current = standing - min
    needed = if max == :infinity, do: 0, else: max - min

    {level, current, needed}
  end

  @doc "Get maximum standing value."
  @spec max_standing() :: integer()
  def max_standing, do: 42000

  @doc "Get minimum standing value."
  @spec min_standing() :: integer()
  def min_standing, do: -42000

  # Gameplay Effects

  @doc "Get vendor discount percentage for reputation level."
  @spec vendor_discount(level()) :: float()
  def vendor_discount(:hated), do: 0.0
  def vendor_discount(:hostile), do: 0.0
  def vendor_discount(:unfriendly), do: 0.0
  def vendor_discount(:neutral), do: 0.0
  # 5% discount
  def vendor_discount(:friendly), do: 0.05
  # 10% discount
  def vendor_discount(:honored), do: 0.10
  # 15% discount
  def vendor_discount(:revered), do: 0.15
  # 20% discount
  def vendor_discount(:exalted), do: 0.20

  @doc "Get vendor discount for a standing value."
  @spec vendor_discount_for_standing(integer()) :: float()
  def vendor_discount_for_standing(standing) do
    standing |> standing_to_level() |> vendor_discount()
  end

  @doc "Check if player can interact with faction NPCs."
  @spec can_interact?(level()) :: boolean()
  def can_interact?(:hated), do: false
  def can_interact?(:hostile), do: false
  def can_interact?(_), do: true

  @doc "Check if player can purchase from faction vendors."
  @spec can_purchase?(level()) :: boolean()
  def can_purchase?(:hated), do: false
  def can_purchase?(:hostile), do: false
  def can_purchase?(:unfriendly), do: false
  def can_purchase?(_), do: true

  @doc "Check if reputation meets minimum level requirement."
  @spec meets_requirement?(integer(), level()) :: boolean()
  def meets_requirement?(standing, required_level) do
    current_level = standing_to_level(standing)
    level_to_index(current_level) >= level_to_index(required_level)
  end

  @doc "Get all reputation levels with their boundaries."
  @spec levels() :: [{level(), integer(), integer() | :infinity}]
  def levels, do: @levels

  # Private helpers

  defp level_to_index(:hated), do: 0
  defp level_to_index(:hostile), do: 1
  defp level_to_index(:unfriendly), do: 2
  defp level_to_index(:neutral), do: 3
  defp level_to_index(:friendly), do: 4
  defp level_to_index(:honored), do: 5
  defp level_to_index(:revered), do: 6
  defp level_to_index(:exalted), do: 7
end
