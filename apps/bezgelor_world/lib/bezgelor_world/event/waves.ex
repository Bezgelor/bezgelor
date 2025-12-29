defmodule BezgelorWorld.Event.Waves do
  @moduledoc """
  Wave mechanics for public events.

  This module contains pure functions for:
  - Creating wave state from definitions
  - Tracking wave progress
  - Checking wave completion conditions

  ## Wave Events

  Wave-based events spawn enemies in sequential waves. Players must defeat
  all enemies in each wave before proceeding to the next. Each wave can have:
  - Enemy count to defeat
  - Time limit (optional)

  ## Wave State Structure

  Wave state contains:
  - `current_wave` - The current wave number (1-indexed)
  - `total_waves` - Total number of waves in the event
  - `enemies_spawned` - Number of enemies spawned this wave
  - `enemies_killed` - Number of enemies killed this wave
  - `wave_timer` - Timer reference for wave time limit (or nil)
  """

  @type wave_state :: %{
          current_wave: non_neg_integer(),
          total_waves: non_neg_integer(),
          enemies_spawned: non_neg_integer(),
          enemies_killed: non_neg_integer(),
          wave_timer: reference() | nil
        }

  @doc """
  Create a new wave state for starting a wave.

  ## Parameters

  - `wave_number` - The wave number (1-indexed)
  - `wave_def` - The wave definition map from event data
  - `total_waves` - Total number of waves in the event

  ## Returns

  A new wave_state map ready for tracking.
  """
  @spec create_wave_state(non_neg_integer(), map(), non_neg_integer()) :: wave_state()
  def create_wave_state(wave_number, wave_def, total_waves) do
    enemy_count = wave_def["enemy_count"] || 10

    %{
      current_wave: wave_number,
      total_waves: total_waves,
      enemies_spawned: enemy_count,
      enemies_killed: 0,
      wave_timer: nil
    }
  end

  @doc """
  Record an enemy kill and return updated wave state.

  ## Parameters

  - `wave_state` - Current wave state

  ## Returns

  Updated wave_state with incremented kill count.
  """
  @spec record_enemy_killed(wave_state()) :: wave_state()
  def record_enemy_killed(wave_state) do
    %{wave_state | enemies_killed: wave_state.enemies_killed + 1}
  end

  @doc """
  Check if the current wave is complete.

  ## Parameters

  - `wave_state` - Current wave state

  ## Returns

  `true` if all enemies have been killed, `false` otherwise.
  """
  @spec is_wave_complete?(wave_state()) :: boolean()
  def is_wave_complete?(wave_state) do
    wave_state.enemies_killed >= wave_state.enemies_spawned
  end

  @doc """
  Check if there are more waves after the current one.

  ## Parameters

  - `wave_state` - Current wave state

  ## Returns

  `true` if more waves remain, `false` if this is the last wave.
  """
  @spec has_more_waves?(wave_state()) :: boolean()
  def has_more_waves?(wave_state) do
    wave_state.current_wave < wave_state.total_waves
  end

  @doc """
  Calculate remaining enemies in the current wave.

  ## Parameters

  - `wave_state` - Current wave state

  ## Returns

  Number of enemies still alive.
  """
  @spec remaining_enemies(wave_state()) :: non_neg_integer()
  def remaining_enemies(wave_state) do
    max(0, wave_state.enemies_spawned - wave_state.enemies_killed)
  end

  @doc """
  Calculate wave progress as a percentage.

  ## Parameters

  - `wave_state` - Current wave state

  ## Returns

  Progress as integer percentage (0-100).
  """
  @spec wave_progress_percent(wave_state()) :: non_neg_integer()
  def wave_progress_percent(%{enemies_spawned: 0}), do: 100
  def wave_progress_percent(wave_state) do
    div(wave_state.enemies_killed * 100, wave_state.enemies_spawned)
  end

  @doc """
  Calculate overall event progress across all waves.

  ## Parameters

  - `wave_state` - Current wave state

  ## Returns

  Progress as integer percentage (0-100).
  """
  @spec overall_progress_percent(wave_state()) :: non_neg_integer()
  def overall_progress_percent(%{total_waves: 0}), do: 100
  def overall_progress_percent(wave_state) do
    completed_waves = wave_state.current_wave - 1
    current_progress = wave_progress_percent(wave_state)

    # Weight each wave equally
    per_wave = div(100, wave_state.total_waves)
    completed_waves * per_wave + div(current_progress * per_wave, 100)
  end

  @doc """
  Get a summary of wave status.

  ## Parameters

  - `wave_state` - Current wave state

  ## Returns

  Map with wave status information.
  """
  @spec wave_summary(wave_state()) :: map()
  def wave_summary(wave_state) do
    %{
      wave: wave_state.current_wave,
      total_waves: wave_state.total_waves,
      enemies_killed: wave_state.enemies_killed,
      enemies_remaining: remaining_enemies(wave_state),
      wave_complete: is_wave_complete?(wave_state),
      has_more_waves: has_more_waves?(wave_state),
      progress_percent: wave_progress_percent(wave_state)
    }
  end

  @doc """
  Get the wave definition for a specific wave number.

  ## Parameters

  - `event_def` - The event definition map
  - `wave_number` - Wave number to get (1-indexed)

  ## Returns

  The wave definition map, or nil if not found.
  """
  @spec get_wave_def(map(), non_neg_integer()) :: map() | nil
  def get_wave_def(event_def, wave_number) do
    waves = event_def["waves"] || []
    Enum.at(waves, wave_number - 1)
  end

  @doc """
  Get the total number of waves in an event.

  ## Parameters

  - `event_def` - The event definition map

  ## Returns

  Total number of waves.
  """
  @spec total_waves(map()) :: non_neg_integer()
  def total_waves(event_def) do
    length(event_def["waves"] || [])
  end

  @doc """
  Check if an event has wave mechanics.

  ## Parameters

  - `event_def` - The event definition map

  ## Returns

  `true` if the event uses waves, `false` otherwise.
  """
  @spec has_waves?(map()) :: boolean()
  def has_waves?(event_def) do
    waves = event_def["waves"] || []
    length(waves) > 0
  end

  @doc """
  Set the wave timer reference.

  ## Parameters

  - `wave_state` - Current wave state
  - `timer_ref` - Timer reference or nil

  ## Returns

  Updated wave_state with timer set.
  """
  @spec set_wave_timer(wave_state(), reference() | nil) :: wave_state()
  def set_wave_timer(wave_state, timer_ref) do
    %{wave_state | wave_timer: timer_ref}
  end
end
