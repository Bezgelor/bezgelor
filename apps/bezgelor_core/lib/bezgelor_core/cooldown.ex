defmodule BezgelorCore.Cooldown do
  @moduledoc """
  Cooldown tracking for spells and abilities.

  ## Overview

  This module provides functions for managing spell cooldowns. Cooldowns are
  tracked using monotonic time to ensure accuracy across process restarts
  and avoid clock skew issues.

  ## Cooldown State

  Cooldown state is a map from spell_id to expiration time (monotonic):

      %{
        1 => 1234567890,  # spell 1 on cooldown until this time
        3 => 1234560000,  # spell 3 on cooldown
        :gcd => 1234555000  # global cooldown
      }

  ## Usage

      iex> state = Cooldown.new()
      %{}

      iex> state = Cooldown.set(state, 1, 5000)  # 5 second cooldown
      %{1 => ...}

      iex> Cooldown.ready?(state, 1)
      false

      iex> Cooldown.remaining(state, 1)
      4500  # milliseconds remaining
  """

  @type spell_id :: non_neg_integer() | :gcd
  @type cooldown_state :: %{spell_id() => integer()}

  @doc """
  Create a new empty cooldown state.
  """
  @spec new() :: cooldown_state()
  def new, do: %{}

  @doc """
  Set a cooldown for a spell.

  ## Parameters

  - `state` - Current cooldown state
  - `spell_id` - Spell ID or `:gcd` for global cooldown
  - `duration_ms` - Duration in milliseconds

  ## Examples

      iex> state = Cooldown.set(%{}, 1, 5000)
      iex> Cooldown.ready?(state, 1)
      false
  """
  @spec set(cooldown_state(), spell_id(), non_neg_integer()) :: cooldown_state()
  def set(state, spell_id, duration_ms) when duration_ms > 0 do
    expires_at = System.monotonic_time(:millisecond) + duration_ms
    Map.put(state, spell_id, expires_at)
  end

  def set(state, _spell_id, 0), do: state

  @doc """
  Set the global cooldown.

  ## Parameters

  - `state` - Current cooldown state
  - `duration_ms` - GCD duration in milliseconds (default 1000)
  """
  @spec set_gcd(cooldown_state(), non_neg_integer()) :: cooldown_state()
  def set_gcd(state, duration_ms \\ 1000) do
    set(state, :gcd, duration_ms)
  end

  @doc """
  Check if a spell is ready to cast (not on cooldown).
  """
  @spec ready?(cooldown_state(), spell_id()) :: boolean()
  def ready?(state, spell_id) do
    remaining(state, spell_id) == 0
  end

  @doc """
  Check if the global cooldown is active.
  """
  @spec gcd_active?(cooldown_state()) :: boolean()
  def gcd_active?(state) do
    not ready?(state, :gcd)
  end

  @doc """
  Get remaining cooldown time in milliseconds.

  Returns 0 if the spell is ready.
  """
  @spec remaining(cooldown_state(), spell_id()) :: non_neg_integer()
  def remaining(state, spell_id) do
    case Map.get(state, spell_id) do
      nil ->
        0

      expires_at ->
        now = System.monotonic_time(:millisecond)
        max(0, expires_at - now)
    end
  end

  @doc """
  Get remaining GCD time in milliseconds.
  """
  @spec gcd_remaining(cooldown_state()) :: non_neg_integer()
  def gcd_remaining(state) do
    remaining(state, :gcd)
  end

  @doc """
  Clear a specific cooldown.
  """
  @spec clear(cooldown_state(), spell_id()) :: cooldown_state()
  def clear(state, spell_id) do
    Map.delete(state, spell_id)
  end

  @doc """
  Clear all cooldowns (including GCD).
  """
  @spec clear_all(cooldown_state()) :: cooldown_state()
  def clear_all(_state) do
    new()
  end

  @doc """
  Clear only the global cooldown.
  """
  @spec clear_gcd(cooldown_state()) :: cooldown_state()
  def clear_gcd(state) do
    clear(state, :gcd)
  end

  @doc """
  Cleanup expired cooldowns from state.

  This is optional but can reduce memory usage for long-running sessions.
  """
  @spec cleanup(cooldown_state()) :: cooldown_state()
  def cleanup(state) do
    now = System.monotonic_time(:millisecond)

    Map.filter(state, fn {_spell_id, expires_at} ->
      expires_at > now
    end)
  end

  @doc """
  Get all active cooldowns with remaining times.

  Returns a map of spell_id => remaining_ms for spells still on cooldown.
  """
  @spec active_cooldowns(cooldown_state()) :: %{spell_id() => non_neg_integer()}
  def active_cooldowns(state) do
    now = System.monotonic_time(:millisecond)

    state
    |> Enum.map(fn {spell_id, expires_at} ->
      {spell_id, max(0, expires_at - now)}
    end)
    |> Enum.filter(fn {_spell_id, remaining} -> remaining > 0 end)
    |> Map.new()
  end

  @doc """
  Check if a spell can be cast (not on cooldown and GCD ready).
  """
  @spec can_cast?(cooldown_state(), spell_id(), boolean()) :: boolean()
  def can_cast?(state, spell_id, triggers_gcd \\ true) do
    spell_ready = ready?(state, spell_id)
    gcd_ready = not triggers_gcd or ready?(state, :gcd)

    spell_ready and gcd_ready
  end

  @doc """
  Apply cooldowns after casting a spell.

  Sets both the spell cooldown and GCD (if applicable).

  ## Parameters

  - `state` - Current cooldown state
  - `spell_id` - Spell that was cast
  - `spell_cooldown` - Spell's cooldown duration in ms
  - `triggers_gcd` - Whether to apply global cooldown
  - `gcd_duration` - GCD duration in ms (default 1000)
  """
  @spec apply_cast(cooldown_state(), spell_id(), non_neg_integer(), boolean(), non_neg_integer()) ::
          cooldown_state()
  def apply_cast(state, spell_id, spell_cooldown, triggers_gcd, gcd_duration \\ 1000) do
    state = set(state, spell_id, spell_cooldown)

    if triggers_gcd do
      set_gcd(state, gcd_duration)
    else
      state
    end
  end
end
