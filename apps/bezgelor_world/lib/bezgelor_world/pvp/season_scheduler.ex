defmodule BezgelorWorld.PvP.SeasonScheduler do
  @moduledoc """
  Manages PvP season lifecycle with scheduled transitions.

  Runs checks daily to:
  - Start new seasons when scheduled
  - End seasons when their end_date is reached
  - Apply weekly rating decay (on Tuesdays)
  """

  use GenServer

  require Logger

  alias BezgelorDb.PvP
  alias BezgelorWorld.PvP.{Season, RatingDecay}

  @check_interval_ms 24 * 60 * 60 * 1000
  @decay_day_of_week 2

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Force a season check (useful for testing or admin commands).
  """
  @spec force_check() :: :ok
  def force_check do
    GenServer.cast(__MODULE__, :force_check)
  end

  @doc """
  Force rating decay application (useful for testing or admin commands).
  """
  @spec force_decay() :: {:ok, integer()}
  def force_decay do
    GenServer.call(__MODULE__, :force_decay)
  end

  @doc """
  Get the scheduler state.
  """
  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("SeasonScheduler started")

    state = %{
      last_decay_week: nil,
      last_check_at: nil,
      seasons_ended: 0,
      decays_applied: 0
    }

    schedule_check()

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:force_decay, _from, state) do
    case RatingDecay.process_weekly_decay() do
      {:ok, count} ->
        state = %{
          state
          | decays_applied: state.decays_applied + count,
            last_decay_week: current_week_number()
        }

        {:reply, {:ok, count}, state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_cast(:force_check, state) do
    state = check_season_transitions(state)
    state = maybe_apply_decay(state)
    {:noreply, %{state | last_check_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:check_seasons, state) do
    state = check_season_transitions(state)
    state = maybe_apply_decay(state)
    state = %{state | last_check_at: DateTime.utc_now()}
    schedule_check()
    {:noreply, state}
  end

  # Private functions

  defp schedule_check do
    Process.send_after(self(), :check_seasons, @check_interval_ms)
  end

  defp check_season_transitions(state) do
    now = DateTime.utc_now()

    case PvP.get_active_season() do
      nil ->
        Logger.debug("No active PvP season")
        state

      season ->
        if DateTime.compare(now, season.end_date) == :gt do
          Logger.info("Ending PvP season #{season.season_number}")

          case Season.end_season(season.id) do
            {:ok, _result} ->
              %{state | seasons_ended: state.seasons_ended + 1}

            {:error, reason} ->
              Logger.error("Failed to end season #{season.season_number}: #{inspect(reason)}")
              state
          end
        else
          days_remaining = DateTime.diff(season.end_date, now, :day)
          Logger.debug("Season #{season.season_number} has #{days_remaining} days remaining")
          state
        end
    end
  end

  defp maybe_apply_decay(state) do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)
    week_number = current_week_number()

    if day_of_week == @decay_day_of_week and state.last_decay_week != week_number do
      Logger.info("Applying weekly rating decay (Tuesday maintenance)")

      case RatingDecay.process_weekly_decay() do
        {:ok, count} ->
          Logger.info("Applied decay to #{count} ratings")
          %{state | last_decay_week: week_number, decays_applied: state.decays_applied + count}

        {:error, reason} ->
          Logger.error("Failed to apply rating decay: #{inspect(reason)}")
          state
      end
    else
      state
    end
  end

  defp current_week_number do
    today = Date.utc_today()
    div(Date.to_gregorian_days(today), 7)
  end
end
