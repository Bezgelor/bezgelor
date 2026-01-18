defmodule BezgelorWorld.Event.WorldBoss do
  @moduledoc """
  World boss mechanics and phase transition logic.

  This module contains pure functions for:
  - Checking boss phase transitions based on health thresholds
  - Calculating boss damage and health percentages
  - Managing boss engagement state

  ## World Boss Phases

  World bosses can have multiple phases defined in their boss_def.
  Each phase has a `health_threshold` percentage that triggers the transition.
  Phases are numbered starting from 1.

  ## Boss State Structure

  World boss state contains:
  - `boss_id` - The world boss definition ID
  - `boss_def` - The full boss definition map
  - `creature_id` - Optional spawned creature ID
  - `phase` - Current phase number (starts at 1)
  - `health_current` - Current health points
  - `health_max` - Maximum health points
  - `engaged_at` - When combat began (nil if not engaged)
  - `participants` - MapSet of participating character IDs
  - `contributions` - Map of character_id => damage dealt
  """

  require Logger

  @type boss_state :: %{
          boss_id: non_neg_integer(),
          boss_def: map(),
          creature_id: non_neg_integer() | nil,
          phase: non_neg_integer(),
          health_current: non_neg_integer(),
          health_max: non_neg_integer(),
          engaged_at: DateTime.t() | nil,
          participants: MapSet.t(non_neg_integer()),
          contributions: %{non_neg_integer() => non_neg_integer()}
        }

  @doc """
  Check if the boss should transition to a new phase based on health.

  Examines the boss_def phases and their health thresholds to determine
  if a phase transition should occur.

  ## Parameters

  - `boss_state` - The current world boss state

  ## Returns

  Updated boss_state with new phase if transition occurred, unchanged otherwise.
  """
  @spec check_phase_transition(boss_state()) :: boss_state()
  def check_phase_transition(boss_state) do
    phases = boss_state.boss_def["phases"] || []
    health_percent = calculate_health_percent(boss_state)

    # Find the appropriate phase based on health
    new_phase =
      phases
      |> Enum.with_index(1)
      |> Enum.find_value(boss_state.phase, fn {phase_def, phase_num} ->
        threshold = phase_def["health_threshold"] || 0

        if health_percent <= threshold and phase_num > boss_state.phase do
          phase_num
        else
          nil
        end
      end)

    if new_phase != boss_state.phase do
      Logger.info("World boss #{boss_state.boss_id} transitioned to phase #{new_phase}")
      %{boss_state | phase: new_phase}
    else
      boss_state
    end
  end

  @doc """
  Calculate the boss's current health percentage.

  ## Parameters

  - `boss_state` - The world boss state

  ## Returns

  Health as an integer percentage (0-100).
  """
  @spec calculate_health_percent(boss_state()) :: non_neg_integer()
  def calculate_health_percent(%{health_max: 0}), do: 0
  def calculate_health_percent(%{health_current: current, health_max: max}) do
    div(current * 100, max)
  end

  @doc """
  Check if the boss is dead (health <= 0).

  ## Parameters

  - `boss_state` - The world boss state

  ## Returns

  `true` if boss is dead, `false` otherwise.
  """
  @spec is_dead?(boss_state()) :: boolean()
  def is_dead?(%{health_current: health}) when health <= 0, do: true
  def is_dead?(_boss_state), do: false

  @doc """
  Apply damage to the boss and record the contribution.

  ## Parameters

  - `boss_state` - The world boss state
  - `character_id` - The character dealing damage
  - `damage` - Amount of damage dealt

  ## Returns

  Updated boss_state with reduced health and updated contribution tracking.
  """
  @spec apply_damage(boss_state(), non_neg_integer(), non_neg_integer()) :: boss_state()
  def apply_damage(boss_state, character_id, damage) do
    new_health = max(0, boss_state.health_current - damage)

    contributions =
      Map.update(boss_state.contributions, character_id, damage, &(&1 + damage))

    participants = MapSet.put(boss_state.participants, character_id)

    # Mark engagement time if this is first damage
    engaged_at =
      if is_nil(boss_state.engaged_at) do
        DateTime.utc_now()
      else
        boss_state.engaged_at
      end

    %{boss_state |
      health_current: new_health,
      contributions: contributions,
      participants: participants,
      engaged_at: engaged_at
    }
  end

  @doc """
  Calculate the kill time in milliseconds.

  ## Parameters

  - `boss_state` - The world boss state

  ## Returns

  Kill time in milliseconds, or 0 if boss was never engaged.
  """
  @spec calculate_kill_time(boss_state()) :: non_neg_integer()
  def calculate_kill_time(%{engaged_at: nil}), do: 0
  def calculate_kill_time(%{engaged_at: engaged_at}) do
    DateTime.diff(DateTime.utc_now(), engaged_at, :millisecond)
  end

  @doc """
  Get the top contributors sorted by damage dealt.

  ## Parameters

  - `boss_state` - The world boss state
  - `limit` - Maximum number of contributors to return (default: 10)

  ## Returns

  List of {character_id, damage} tuples sorted by damage descending.
  """
  @spec top_contributors(boss_state(), non_neg_integer()) :: [{non_neg_integer(), non_neg_integer()}]
  def top_contributors(boss_state, limit \\ 10) do
    boss_state.contributions
    |> Enum.sort_by(fn {_id, damage} -> damage end, :desc)
    |> Enum.take(limit)
  end

  @doc """
  Get a participant's contribution percentage.

  ## Parameters

  - `boss_state` - The world boss state
  - `character_id` - The character to check

  ## Returns

  Contribution as percentage of total damage dealt (0-100).
  """
  @spec contribution_percent(boss_state(), non_neg_integer()) :: non_neg_integer()
  def contribution_percent(boss_state, character_id) do
    total_damage = boss_state.health_max
    player_damage = Map.get(boss_state.contributions, character_id, 0)

    if total_damage > 0 do
      div(player_damage * 100, total_damage)
    else
      0
    end
  end

  @doc """
  Create initial boss state from a boss definition and position.

  ## Parameters

  - `boss_id` - The world boss ID
  - `boss_def` - The boss definition map from game data
  - `creature_id` - Optional spawned creature entity ID

  ## Returns

  A new boss_state map.
  """
  @spec create_boss_state(non_neg_integer(), map(), non_neg_integer() | nil) :: boss_state()
  def create_boss_state(boss_id, boss_def, creature_id \\ nil) do
    health = boss_def["health"] || 1_000_000

    %{
      boss_id: boss_id,
      boss_def: boss_def,
      creature_id: creature_id,
      phase: 1,
      health_current: health,
      health_max: health,
      engaged_at: nil,
      participants: MapSet.new(),
      contributions: %{}
    }
  end

  @doc """
  Get the current phase definition for a boss.

  ## Parameters

  - `boss_state` - The world boss state

  ## Returns

  The phase definition map, or an empty map if not found.
  """
  @spec current_phase_def(boss_state()) :: map()
  def current_phase_def(boss_state) do
    phases = boss_state.boss_def["phases"] || []
    Enum.at(phases, boss_state.phase - 1) || %{}
  end

  @doc """
  Check if boss is engaged in combat.

  ## Parameters

  - `boss_state` - The world boss state

  ## Returns

  `true` if boss has been damaged, `false` otherwise.
  """
  @spec engaged?(boss_state()) :: boolean()
  def engaged?(%{engaged_at: nil}), do: false
  def engaged?(_boss_state), do: true
end
