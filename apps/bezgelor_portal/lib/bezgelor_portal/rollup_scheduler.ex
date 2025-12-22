defmodule BezgelorPortal.RollupScheduler do
  @moduledoc """
  GenServer that periodically aggregates raw telemetry events into time-based buckets.

  ## Aggregation Strategy

  Runs three periodic rollup jobs:
  - **Minute rollup** (every 1 minute): Raw events → Minute buckets
  - **Hour rollup** (every 1 hour): Minute buckets → Hour buckets
  - **Day rollup** (every 24 hours): Hour buckets → Day buckets + purge old data

  All rollups use the LAST COMPLETE interval to ensure idempotent aggregation.
  For example, at 10:03:45, the minute rollup processes 10:02:00-10:02:59 (not the current partial minute).

  ## Retention Policy

  - Raw events: 48 hours
  - Minute buckets: 14 days
  - Hour buckets: 90 days
  - Day buckets: 365 days

  ## Implementation Details

  - Uses incremental aggregation via `Enum.reduce` to avoid loading all events into memory
  - Streams data from database using `Repo.stream/2` with transactions
  - Runs startup rollup asynchronously via Task to avoid blocking supervision tree
  - All database operations use `BezgelorDb.Metrics` context
  """

  use GenServer
  require Logger

  alias BezgelorDb.{Metrics, Repo}
  alias BezgelorDb.Schema.TelemetryEvent

  import Ecto.Query

  # Rollup intervals in milliseconds
  @minute_interval :timer.minutes(1)
  @hour_interval :timer.hours(1)
  @day_interval :timer.hours(24)

  # Retention periods in seconds
  @raw_retention_secs 48 * 3600
  @minute_retention_secs 14 * 86400
  @hour_retention_secs 90 * 86400
  @day_retention_secs 365 * 86400

  ## Client API

  @doc """
  Starts the RollupScheduler GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers a manual minute rollup (for testing/admin).
  """
  def trigger_minute_rollup do
    GenServer.call(__MODULE__, :minute_rollup, :timer.seconds(30))
  end

  @doc """
  Triggers a manual hour rollup (for testing/admin).
  """
  def trigger_hour_rollup do
    GenServer.call(__MODULE__, :hour_rollup, :timer.seconds(30))
  end

  @doc """
  Triggers a manual day rollup (for testing/admin).
  """
  def trigger_day_rollup do
    GenServer.call(__MODULE__, :day_rollup, :timer.seconds(30))
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    skip_startup = Keyword.get(opts, :skip_startup_rollup, false)

    # Schedule periodic rollups
    schedule_minute_rollup()
    schedule_hour_rollup()
    schedule_day_rollup()

    # Run startup rollup asynchronously unless skipped (for tests)
    unless skip_startup do
      # TODO: Use BezgelorPortal.TaskSupervisor when available
      Task.start(fn -> perform_startup_rollup() end)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:minute_rollup, state) do
    perform_minute_rollup()
    schedule_minute_rollup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:hour_rollup, state) do
    perform_hour_rollup()
    schedule_hour_rollup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:day_rollup, state) do
    perform_day_rollup()
    schedule_day_rollup()
    {:noreply, state}
  end

  @impl true
  def handle_call(:minute_rollup, _from, state) do
    result = perform_minute_rollup()
    {:reply, result, state}
  end

  @impl true
  def handle_call(:hour_rollup, _from, state) do
    result = perform_hour_rollup()
    {:reply, result, state}
  end

  @impl true
  def handle_call(:day_rollup, _from, state) do
    result = perform_day_rollup()
    {:reply, result, state}
  end

  ## Private Functions

  defp schedule_minute_rollup do
    Process.send_after(self(), :minute_rollup, @minute_interval)
  end

  defp schedule_hour_rollup do
    Process.send_after(self(), :hour_rollup, @hour_interval)
  end

  defp schedule_day_rollup do
    Process.send_after(self(), :day_rollup, @day_interval)
  end

  defp perform_startup_rollup do
    Logger.info("[RollupScheduler] Starting startup rollup")

    # Run all three rollups on startup to catch up with any missed intervals
    perform_minute_rollup()
    perform_hour_rollup()
    perform_day_rollup()

    Logger.debug("[RollupScheduler] Startup rollup complete")
  end

  defp perform_minute_rollup do
    Logger.debug("[RollupScheduler] Starting minute rollup")

    # Get last complete minute (not current partial minute)
    {bucket_start, bucket_end} = last_complete_minute()

    try do
      # Get all distinct event names for this time range
      event_names = get_distinct_event_names(bucket_start, bucket_end)

      Logger.debug(
        "[RollupScheduler] Minute rollup: #{length(event_names)} event types in range #{bucket_start} - #{bucket_end}"
      )

      # Aggregate each event name
      results =
        Enum.map(event_names, fn event_name ->
          aggregate_events_to_bucket(event_name, bucket_start, bucket_end, :minute)
        end)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      Logger.debug(
        "[RollupScheduler] Minute rollup complete: #{successes} success, #{failures} failures"
      )

      {:ok, %{successes: successes, failures: failures}}
    rescue
      e ->
        Logger.error("[RollupScheduler] Minute rollup failed: #{inspect(e)}")
        {:error, e}
    end
  end

  defp perform_hour_rollup do
    Logger.debug("[RollupScheduler] Starting hour rollup")

    # Get last complete hour
    {bucket_start, bucket_end} = last_complete_hour()

    try do
      # Get all distinct event names for this time range
      event_names = get_distinct_bucket_names(:minute, bucket_start, bucket_end)

      Logger.debug(
        "[RollupScheduler] Hour rollup: #{length(event_names)} event types in range #{bucket_start} - #{bucket_end}"
      )

      # Aggregate each event name
      results =
        Enum.map(event_names, fn event_name ->
          aggregate_buckets_to_bucket(event_name, :minute, bucket_start, bucket_end, :hour)
        end)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      # Purge old minute buckets (older than 14 days)
      purge_cutoff = DateTime.add(DateTime.utc_now(), -@minute_retention_secs, :second)
      {purged, _} = Metrics.purge_buckets_before(:minute, purge_cutoff)

      Logger.debug(
        "[RollupScheduler] Hour rollup complete: #{successes} success, #{failures} failures, #{purged} minute buckets purged"
      )

      {:ok, %{successes: successes, failures: failures, purged: purged}}
    rescue
      e ->
        Logger.error("[RollupScheduler] Hour rollup failed: #{inspect(e)}")
        {:error, e}
    end
  end

  defp perform_day_rollup do
    Logger.debug("[RollupScheduler] Starting day rollup")

    # Get last complete day
    {bucket_start, bucket_end} = last_complete_day()

    try do
      # Get all distinct event names for this time range
      event_names = get_distinct_bucket_names(:hour, bucket_start, bucket_end)

      Logger.debug(
        "[RollupScheduler] Day rollup: #{length(event_names)} event types in range #{bucket_start} - #{bucket_end}"
      )

      # Aggregate each event name
      results =
        Enum.map(event_names, fn event_name ->
          aggregate_buckets_to_bucket(event_name, :hour, bucket_start, bucket_end, :day)
        end)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      # Purge old data
      now = DateTime.utc_now()
      raw_cutoff = DateTime.add(now, -@raw_retention_secs, :second)
      hour_cutoff = DateTime.add(now, -@hour_retention_secs, :second)
      day_cutoff = DateTime.add(now, -@day_retention_secs, :second)

      {purged_events, _} = Metrics.purge_events_before(raw_cutoff)
      {purged_hours, _} = Metrics.purge_buckets_before(:hour, hour_cutoff)
      {purged_days, _} = Metrics.purge_buckets_before(:day, day_cutoff)

      Logger.debug(
        "[RollupScheduler] Day rollup complete: #{successes} success, #{failures} failures, " <>
          "purged #{purged_events} events, #{purged_hours} hour buckets, #{purged_days} day buckets"
      )

      {:ok,
       %{
         successes: successes,
         failures: failures,
         purged_events: purged_events,
         purged_hours: purged_hours,
         purged_days: purged_days
       }}
    rescue
      e ->
        Logger.error("[RollupScheduler] Day rollup failed: #{inspect(e)}")
        {:error, e}
    end
  end

  # Get distinct event names from raw events in time range
  defp get_distinct_event_names(from, to) do
    TelemetryEvent
    |> where([e], e.occurred_at >= ^from and e.occurred_at < ^to)
    |> select([e], e.event_name)
    |> distinct(true)
    |> Repo.all()
  end

  # Get distinct event names from buckets in time range
  defp get_distinct_bucket_names(bucket_type, from, to) do
    BezgelorDb.Schema.TelemetryBucket
    |> where([b], b.bucket_type == ^bucket_type)
    |> where([b], b.bucket_start >= ^from and b.bucket_start < ^to)
    |> select([b], b.event_name)
    |> distinct(true)
    |> Repo.all()
  end

  # Aggregate raw events into a bucket using streaming to avoid OOM
  defp aggregate_events_to_bucket(event_name, bucket_start, bucket_end, bucket_type) do
    query =
      TelemetryEvent
      |> where([e], e.event_name == ^event_name)
      |> where([e], e.occurred_at >= ^bucket_start and e.occurred_at < ^bucket_end)

    # Use transaction + streaming for memory efficiency
    Repo.transaction(fn ->
      agg =
        Repo.stream(query, max_rows: 500)
        |> Enum.reduce(new_aggregator(), fn event, acc ->
          update_aggregator(acc, event)
        end)

      # Only upsert if we have events
      if agg.count > 0 do
        bucket_attrs = %{
          event_name: event_name,
          bucket_type: bucket_type,
          bucket_start: bucket_start,
          count: agg.count,
          sum_values: agg.sum_values,
          min_values: agg.min_values,
          max_values: agg.max_values,
          metadata_counts: agg.metadata_counts
        }

        case Metrics.upsert_bucket(bucket_attrs) do
          {:ok, bucket} -> bucket
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        # No events to aggregate
        nil
      end
    end)
  end

  # Aggregate source buckets into a destination bucket using streaming
  defp aggregate_buckets_to_bucket(
         event_name,
         source_type,
         bucket_start,
         bucket_end,
         dest_type
       ) do
    query =
      BezgelorDb.Schema.TelemetryBucket
      |> where([b], b.event_name == ^event_name)
      |> where([b], b.bucket_type == ^source_type)
      |> where([b], b.bucket_start >= ^bucket_start and b.bucket_start < ^bucket_end)

    # Use transaction + streaming for memory efficiency
    Repo.transaction(fn ->
      agg =
        Repo.stream(query, max_rows: 500)
        |> Enum.reduce(new_aggregator(), fn bucket, acc ->
          update_aggregator_from_bucket(acc, bucket)
        end)

      # Only upsert if we have data
      if agg.count > 0 do
        bucket_attrs = %{
          event_name: event_name,
          bucket_type: dest_type,
          bucket_start: bucket_start,
          count: agg.count,
          sum_values: agg.sum_values,
          min_values: agg.min_values,
          max_values: agg.max_values,
          metadata_counts: agg.metadata_counts
        }

        case Metrics.upsert_bucket(bucket_attrs) do
          {:ok, bucket} -> bucket
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        # No buckets to aggregate
        nil
      end
    end)
  end

  # Initialize a new aggregator
  defp new_aggregator do
    %{
      count: 0,
      sum_values: %{},
      min_values: %{},
      max_values: %{},
      metadata_counts: %{}
    }
  end

  # Update aggregator with a raw event
  defp update_aggregator(agg, event) do
    %{
      count: agg.count + 1,
      sum_values: merge_sums(agg.sum_values, event.measurements),
      min_values: merge_mins(agg.min_values, event.measurements),
      max_values: merge_maxs(agg.max_values, event.measurements),
      metadata_counts: merge_metadata_counts(agg.metadata_counts, event.metadata)
    }
  end

  # Update aggregator with a bucket
  defp update_aggregator_from_bucket(agg, bucket) do
    %{
      count: agg.count + bucket.count,
      sum_values: merge_sums(agg.sum_values, bucket.sum_values),
      min_values: merge_mins(agg.min_values, bucket.min_values),
      max_values: merge_maxs(agg.max_values, bucket.max_values),
      metadata_counts: merge_metadata_counts(agg.metadata_counts, bucket.metadata_counts)
    }
  end

  # Merge sum values
  defp merge_sums(existing, new) do
    Map.merge(existing, new, fn _key, v1, v2 -> v1 + v2 end)
  end

  # Merge min values
  defp merge_mins(existing, new) do
    Map.merge(existing, new, fn _key, v1, v2 -> min(v1, v2) end)
  end

  # Merge max values
  defp merge_maxs(existing, new) do
    Map.merge(existing, new, fn _key, v1, v2 -> max(v1, v2) end)
  end

  # Merge metadata counts
  defp merge_metadata_counts(existing, new) when is_map(new) do
    # Flatten metadata into "key:value" strings for counting
    flattened =
      Enum.reduce(new, %{}, fn {key, val}, acc ->
        count_key = "#{key}:#{val}"
        Map.put(acc, count_key, 1)
      end)

    Map.merge(existing, flattened, fn _key, v1, v2 -> v1 + v2 end)
  end

  defp merge_metadata_counts(existing, _new), do: existing

  # Get last complete minute interval
  defp last_complete_minute do
    now = DateTime.utc_now()
    # Round down to start of last complete minute
    bucket_start =
      now
      |> DateTime.add(-60, :second)
      |> DateTime.truncate(:microsecond)
      |> Map.put(:second, 0)
      |> Map.put(:microsecond, {0, 6})

    bucket_end = DateTime.add(bucket_start, 60, :second)

    {bucket_start, bucket_end}
  end

  # Get last complete hour interval
  defp last_complete_hour do
    now = DateTime.utc_now()
    # Round down to start of last complete hour
    bucket_start =
      now
      |> DateTime.add(-3600, :second)
      |> DateTime.truncate(:microsecond)
      |> Map.put(:minute, 0)
      |> Map.put(:second, 0)
      |> Map.put(:microsecond, {0, 6})

    bucket_end = DateTime.add(bucket_start, 3600, :second)

    {bucket_start, bucket_end}
  end

  # Get last complete day interval
  defp last_complete_day do
    now = DateTime.utc_now()
    # Round down to start of last complete day (UTC midnight)
    bucket_start =
      now
      |> DateTime.add(-86400, :second)
      |> DateTime.to_date()
      |> DateTime.new!(~T[00:00:00.000000])

    bucket_end = DateTime.add(bucket_start, 86400, :second)

    {bucket_start, bucket_end}
  end
end
