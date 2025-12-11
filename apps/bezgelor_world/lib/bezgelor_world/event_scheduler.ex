defmodule BezgelorWorld.EventScheduler do
  @moduledoc """
  Periodic scheduler for public events and world bosses.

  ## Overview

  The EventScheduler runs periodically to:
  - Check for scheduled events that are due to trigger
  - Start random events based on configured windows
  - Manage world boss spawn windows
  - Chain events based on completion triggers

  ## Trigger Types

  - `:timer` - Fixed interval (e.g., every 2 hours)
  - `:random_window` - Random time within a window
  - `:player_count` - When zone population reaches threshold
  - `:chain` - After another event completes
  - `:manual` - Only via admin command
  """

  use GenServer

  alias BezgelorDb.PublicEvents
  alias BezgelorWorld.EventManager

  require Logger

  @check_interval_ms 60_000

  ## Client API

  @doc "Start the EventScheduler."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Force a schedule check now."
  def check_now do
    GenServer.cast(__MODULE__, :check_schedules)
  end

  @doc "Manually trigger an event in a zone."
  @spec trigger_event(non_neg_integer(), non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def trigger_event(event_id, zone_id) do
    GenServer.call(__MODULE__, {:trigger_event, event_id, zone_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule first check
    schedule_check()

    state = %{
      last_check: nil,
      triggered_count: 0
    }

    Logger.info("EventScheduler started, checking every #{@check_interval_ms}ms")
    {:ok, state}
  end

  @impl true
  def handle_cast(:check_schedules, state) do
    state = check_all_schedules(state)
    {:noreply, state}
  end

  @impl true
  def handle_call({:trigger_event, event_id, zone_id}, _from, state) do
    result = do_trigger_event(event_id, zone_id)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:check_schedules, state) do
    state = check_all_schedules(state)
    schedule_check()
    {:noreply, state}
  end

  ## Private Helpers

  defp schedule_check do
    Process.send_after(self(), :check_schedules, @check_interval_ms)
  end

  defp check_all_schedules(state) do
    now = DateTime.utc_now()

    # Get schedules that are due
    due_schedules = PublicEvents.get_due_schedules()

    Enum.each(due_schedules, fn schedule ->
      process_schedule(schedule, now)
    end)

    # Check world boss spawn windows
    check_world_boss_windows(now)

    %{state | last_check: now, triggered_count: state.triggered_count + length(due_schedules)}
  end

  defp process_schedule(schedule, now) do
    Logger.debug("Processing schedule #{schedule.id} for event #{schedule.event_id}")

    case schedule.trigger_type do
      :timer ->
        trigger_scheduled_event(schedule)
        next_trigger = calculate_next_timer_trigger(schedule, now)
        PublicEvents.mark_triggered(schedule.id, next_trigger)

      :random_window ->
        trigger_scheduled_event(schedule)
        next_trigger = calculate_next_random_trigger(schedule, now)
        PublicEvents.mark_triggered(schedule.id, next_trigger)

      :player_count ->
        # Check if player count threshold is met
        if zone_meets_player_threshold?(schedule.zone_id, schedule.config) do
          trigger_scheduled_event(schedule)
          # Don't trigger again for a while
          cooldown = Map.get(schedule.config || %{}, "cooldown_hours", 1) * 3600
          next_trigger = DateTime.add(now, cooldown, :second)
          PublicEvents.mark_triggered(schedule.id, next_trigger)
        end

      :chain ->
        # Chain triggers are handled separately by event completion callbacks
        :ok

      :manual ->
        # Manual triggers don't auto-fire
        :ok
    end
  rescue
    error ->
      Logger.error("Error processing schedule #{schedule.id}: #{inspect(error)}")
  end

  defp trigger_scheduled_event(schedule) do
    case do_trigger_event(schedule.event_id, schedule.zone_id) do
      {:ok, instance_id} ->
        Logger.info("Triggered scheduled event #{schedule.event_id} in zone #{schedule.zone_id}, instance #{instance_id}")

      {:error, reason} ->
        Logger.warning("Failed to trigger event #{schedule.event_id}: #{inspect(reason)}")
    end
  end

  defp do_trigger_event(event_id, zone_id) do
    # Find the EventManager for this zone (instance 1 for open world)
    manager = EventManager.via_tuple(zone_id, 1)

    case GenServer.whereis(manager) do
      nil ->
        {:error, :zone_not_running}

      _pid ->
        EventManager.start_event(manager, event_id)
    end
  end

  defp calculate_next_timer_trigger(schedule, now) do
    config = schedule.config || %{}
    interval_hours = Map.get(config, "interval_hours", 2)
    interval_seconds = interval_hours * 3600

    DateTime.add(now, interval_seconds, :second)
  end

  defp calculate_next_random_trigger(schedule, now) do
    config = schedule.config || %{}
    min_hours = Map.get(config, "min_hours", 1)
    max_hours = Map.get(config, "max_hours", 4)

    # Random time within window
    min_seconds = min_hours * 3600
    max_seconds = max_hours * 3600
    random_seconds = :rand.uniform(max_seconds - min_seconds) + min_seconds

    DateTime.add(now, random_seconds, :second)
  end

  defp zone_meets_player_threshold?(zone_id, config) do
    threshold = Map.get(config || %{}, "player_threshold", 10)

    # TODO: Query actual zone player count from Zone.Instance
    # For now, simulate with a random check
    current_players = get_zone_player_count(zone_id)
    current_players >= threshold
  end

  defp get_zone_player_count(_zone_id) do
    # TODO: Implement actual zone player query
    0
  end

  defp check_world_boss_windows(now) do
    # Get bosses in waiting state within their spawn window
    waiting_bosses = PublicEvents.get_waiting_bosses()

    Enum.each(waiting_bosses, fn boss_spawn ->
      if boss_in_spawn_window?(boss_spawn, now) do
        maybe_spawn_world_boss(boss_spawn)
      end
    end)
  end

  defp boss_in_spawn_window?(boss_spawn, now) do
    window_start = boss_spawn.spawn_window_start
    window_end = boss_spawn.spawn_window_end

    cond do
      is_nil(window_start) or is_nil(window_end) ->
        false

      DateTime.compare(now, window_start) == :lt ->
        false

      DateTime.compare(now, window_end) == :gt ->
        false

      true ->
        true
    end
  end

  defp maybe_spawn_world_boss(boss_spawn) do
    # 10% chance per check to spawn while in window
    if :rand.uniform(100) <= 10 do
      case PublicEvents.spawn_boss(boss_spawn.boss_id) do
        {:ok, _} ->
          Logger.info("World boss #{boss_spawn.boss_id} spawned in zone #{boss_spawn.zone_id}")
          # TODO: Notify EventManager to create boss entity

        {:error, reason} ->
          Logger.warning("Failed to spawn world boss #{boss_spawn.boss_id}: #{inspect(reason)}")
      end
    end
  end
end
