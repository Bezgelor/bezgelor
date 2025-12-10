defmodule BezgelorCore.Experience do
  @moduledoc """
  Experience and leveling calculations.

  Handles XP requirements per level, XP gain from kills,
  and level-up mechanics.

  ## XP Formula

  XP required for level N = base * N^2
  With base = 100:
  - Level 2: 400 XP
  - Level 5: 2500 XP
  - Level 10: 10000 XP

  ## XP from Kills

  XP gained is scaled based on level difference:
  - Much higher level (5+): 120% XP
  - Higher level (2-4): 110% XP
  - Same level (-1 to +1): 100% XP
  - Lower level (-2 to -3): 50% XP
  - Much lower (gray, -5+): 10% XP
  """

  @base_xp 100
  @max_level 60

  @doc """
  Calculate XP required for a given level.

  Returns the total XP needed to reach that level from level 1.
  """
  @spec xp_for_level(non_neg_integer()) :: non_neg_integer()
  def xp_for_level(level) when level <= 1, do: 0
  def xp_for_level(level), do: @base_xp * level * level

  @doc """
  Calculate XP required for next level.

  Given current level, returns XP needed to level up.
  """
  @spec xp_to_next_level(non_neg_integer()) :: non_neg_integer()
  def xp_to_next_level(level) when level >= @max_level, do: 0
  def xp_to_next_level(level), do: xp_for_level(level + 1) - xp_for_level(level)

  @doc """
  Calculate XP gained from killing a creature.

  XP is scaled based on level difference between player and creature.
  """
  @spec xp_from_kill(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def xp_from_kill(player_level, creature_level, base_xp) do
    level_diff = creature_level - player_level

    multiplier =
      cond do
        level_diff >= 5 -> 1.2
        level_diff >= 2 -> 1.1
        level_diff <= -5 -> 0.1
        level_diff <= -3 -> 0.5
        true -> 1.0
      end

    trunc(base_xp * multiplier)
  end

  @doc """
  Check if player should level up.

  Returns {:level_up, new_level, remaining_xp} if leveling up,
  or {:no_change, current_level, current_xp} if not.
  """
  @spec check_level_up(non_neg_integer(), non_neg_integer()) ::
          {:level_up, non_neg_integer(), non_neg_integer()}
          | {:no_change, non_neg_integer(), non_neg_integer()}
  def check_level_up(current_level, current_xp) when current_level >= @max_level do
    {:no_change, current_level, current_xp}
  end

  def check_level_up(current_level, current_xp) do
    xp_needed = xp_to_next_level(current_level)

    if current_xp >= xp_needed do
      new_level = current_level + 1
      remaining_xp = current_xp - xp_needed
      # Check for multiple level-ups
      check_level_up_recursive(new_level, remaining_xp, new_level)
    else
      {:no_change, current_level, current_xp}
    end
  end

  defp check_level_up_recursive(level, _xp, _highest_level) when level >= @max_level do
    {:level_up, @max_level, 0}
  end

  defp check_level_up_recursive(level, xp, highest_level) do
    xp_needed = xp_to_next_level(level)

    if xp >= xp_needed do
      check_level_up_recursive(level + 1, xp - xp_needed, level + 1)
    else
      {:level_up, highest_level, xp}
    end
  end

  @doc """
  Apply XP gain and handle level-ups.

  Returns {new_level, new_xp, leveled_up?}
  """
  @spec apply_xp(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer(), boolean()}
  def apply_xp(current_level, current_xp, xp_gained) do
    total_xp = current_xp + xp_gained

    case check_level_up(current_level, total_xp) do
      {:level_up, new_level, remaining_xp} ->
        {new_level, remaining_xp, true}

      {:no_change, level, xp} ->
        {level, xp, false}
    end
  end

  @doc """
  Calculate max health bonus from leveling.

  Each level grants additional max health.
  """
  @spec health_for_level(non_neg_integer()) :: non_neg_integer()
  def health_for_level(level) do
    base_health = 100
    health_per_level = 20
    base_health + (level - 1) * health_per_level
  end

  @doc """
  Get XP percentage towards next level.
  """
  @spec level_progress(non_neg_integer(), non_neg_integer()) :: float()
  def level_progress(level, _xp) when level >= @max_level, do: 1.0

  def level_progress(level, xp) do
    needed = xp_to_next_level(level)
    if needed > 0, do: xp / needed, else: 0.0
  end

  @doc """
  Get the maximum level.
  """
  @spec max_level() :: non_neg_integer()
  def max_level, do: @max_level

  @doc """
  Check if player is at max level.
  """
  @spec at_max_level?(non_neg_integer()) :: boolean()
  def at_max_level?(level), do: level >= @max_level
end
