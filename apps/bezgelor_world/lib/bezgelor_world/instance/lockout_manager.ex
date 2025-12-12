defmodule BezgelorWorld.Instance.LockoutManager do
  @moduledoc """
  Manages instance lockout resets on schedule.

  Handles:
  - Daily reset at configured time (10 AM server default)
  - Weekly reset on configured day (Tuesday default)
  - Broadcasts lockout expiration to affected players
  - Lockout validation for instance entry
  """

  use GenServer
  require Logger

  alias BezgelorDb.Lockouts

  @daily_check_interval :timer.minutes(1)

  # Client API

  @doc """
  Starts the lockout manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if a character is locked out of an instance.

  Returns `true` if the character cannot enter.
  """
  @spec check_lockout(integer(), integer(), String.t()) :: boolean()
  def check_lockout(character_id, instance_id, difficulty) do
    Lockouts.locked_out?(character_id, instance_id, difficulty)
  end

  @doc """
  Creates a new lockout for a character.
  """
  @spec create_lockout(integer(), String.t(), integer(), String.t()) ::
          {:ok, term()} | {:error, term()}
  def create_lockout(character_id, instance_type, instance_id, difficulty) do
    Lockouts.create_lockout(character_id, instance_type, instance_id, difficulty)
  end

  @doc """
  Extends an existing lockout by one week.
  """
  @spec extend_lockout(integer(), integer(), String.t()) :: {:ok, term()} | {:error, term()}
  def extend_lockout(character_id, instance_id, difficulty) do
    Lockouts.extend_lockout(character_id, instance_id, difficulty)
  end

  @doc """
  Gets all active lockouts for a character.
  """
  @spec get_character_lockouts(integer()) :: [term()]
  def get_character_lockouts(character_id) do
    Lockouts.get_character_lockouts(character_id)
  end

  @doc """
  Records a boss kill in a lockout.
  """
  @spec record_boss_kill(integer(), integer(), String.t(), integer()) ::
          {:ok, term()} | {:error, term()}
  def record_boss_kill(character_id, instance_id, difficulty, boss_id) do
    Lockouts.record_boss_kill(character_id, instance_id, difficulty, boss_id)
  end

  @doc """
  Forces cleanup of expired lockouts (admin function).
  """
  @spec clear_expired() :: {integer(), nil}
  def clear_expired do
    GenServer.call(__MODULE__, :clear_expired)
  end

  @doc """
  Gets the current reset schedule.
  """
  @spec get_reset_schedule() :: map()
  def get_reset_schedule do
    GenServer.call(__MODULE__, :get_reset_schedule)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    schedule_next_check()

    lockout_config = Application.get_env(:bezgelor_world, :lockouts, %{})

    state = %{
      daily_reset_hour: lockout_config[:daily_reset_hour] || 10,
      weekly_reset_day: lockout_config[:weekly_reset_day] || :tuesday,
      last_daily_reset: nil,
      last_weekly_reset: nil
    }

    Logger.info("LockoutManager started - Daily reset at #{state.daily_reset_hour}:00, Weekly reset on #{state.weekly_reset_day}")
    {:ok, state}
  end

  @impl true
  def handle_call(:clear_expired, _from, state) do
    result = Lockouts.cleanup_expired()
    Logger.info("Manual lockout cleanup: #{elem(result, 0)} expired lockouts removed")
    {:reply, result, state}
  end

  def handle_call(:get_reset_schedule, _from, state) do
    now = DateTime.utc_now()

    schedule = %{
      daily_reset_hour: state.daily_reset_hour,
      weekly_reset_day: state.weekly_reset_day,
      next_daily_reset: BezgelorDb.Instances.calculate_next_daily_reset(now),
      next_weekly_reset: BezgelorDb.Instances.calculate_next_weekly_reset(now),
      last_daily_reset: state.last_daily_reset,
      last_weekly_reset: state.last_weekly_reset
    }

    {:reply, schedule, state}
  end

  @impl true
  def handle_info(:check_resets, state) do
    state = maybe_trigger_daily_reset(state)
    state = maybe_trigger_weekly_reset(state)
    schedule_next_check()
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp schedule_next_check do
    Process.send_after(self(), :check_resets, @daily_check_interval)
  end

  defp maybe_trigger_daily_reset(state) do
    now = DateTime.utc_now()
    today = Date.utc_today()

    if now.hour >= state.daily_reset_hour and state.last_daily_reset != today do
      Logger.info("Triggering daily lockout reset")
      {count, _} = Lockouts.cleanup_expired()
      Logger.info("Cleaned up #{count} expired lockouts")

      # Broadcast to connected players that daily reset occurred
      broadcast_daily_reset()

      %{state | last_daily_reset: today}
    else
      state
    end
  end

  defp maybe_trigger_weekly_reset(state) do
    today = Date.utc_today()
    now = DateTime.utc_now()
    day_of_week = Date.day_of_week(today)
    reset_day_num = day_number(state.weekly_reset_day)

    if day_of_week == reset_day_num and
         now.hour >= state.daily_reset_hour and
         state.last_weekly_reset != today do
      Logger.info("Triggering weekly lockout reset")

      # Weekly resets are handled by expiration timestamps on the lockouts
      # This just broadcasts the notification
      broadcast_weekly_reset()

      %{state | last_weekly_reset: today}
    else
      state
    end
  end

  defp broadcast_daily_reset do
    # In production: broadcast to all connected players
    # Would send ServerLockoutReset packet
    :ok
  end

  defp broadcast_weekly_reset do
    # In production: broadcast to all connected players
    # Would send ServerLockoutReset packet with weekly flag
    :ok
  end

  defp day_number(:monday), do: 1
  defp day_number(:tuesday), do: 2
  defp day_number(:wednesday), do: 3
  defp day_number(:thursday), do: 4
  defp day_number(:friday), do: 5
  defp day_number(:saturday), do: 6
  defp day_number(:sunday), do: 7
end
