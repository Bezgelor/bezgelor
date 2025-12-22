defmodule BezgelorDb.Metrics do
  @moduledoc """
  Telemetry metrics context.

  Provides functions for storing and querying telemetry events and buckets.

  ## Usage

      # Batch insert events
      Metrics.insert_events([%{event_name: "...", ...}])

      # Query raw events
      events = Metrics.query_events("bezgelor.auth.login_complete", from, to)

      # Query aggregated buckets
      buckets = Metrics.query_buckets("bezgelor.auth.login_complete", :hour, from, to)
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{TelemetryEvent, TelemetryBucket}

  @doc """
  Batch insert telemetry events.

  Returns `{:ok, count}` with number of inserted rows.
  """
  @spec insert_events([map()]) :: {:ok, non_neg_integer()}
  def insert_events([]), do: {:ok, 0}

  def insert_events(events) when is_list(events) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(events, fn event ->
        event
        |> Map.put(:inserted_at, now)
        |> Map.update(:occurred_at, now, &DateTime.truncate(&1, :microsecond))
      end)

    {count, _} = Repo.insert_all(TelemetryEvent, entries)
    {:ok, count}
  end

  @doc """
  Query raw telemetry events by name and time range.
  """
  @spec query_events(String.t(), DateTime.t(), DateTime.t(), keyword()) :: [TelemetryEvent.t()]
  def query_events(event_name, from, to, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)

    TelemetryEvent
    |> where([e], e.event_name == ^event_name)
    |> where([e], e.occurred_at >= ^from and e.occurred_at <= ^to)
    |> order_by([e], desc: e.occurred_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Query aggregated buckets by name, type, and time range.
  """
  @spec query_buckets(String.t(), atom(), DateTime.t(), DateTime.t()) :: [TelemetryBucket.t()]
  def query_buckets(event_name, bucket_type, from, to) do
    TelemetryBucket
    |> where([b], b.event_name == ^event_name)
    |> where([b], b.bucket_type == ^bucket_type)
    |> where([b], b.bucket_start >= ^from and b.bucket_start <= ^to)
    |> order_by([b], asc: b.bucket_start)
    |> Repo.all()
  end

  @doc """
  Upsert a telemetry bucket (insert or update counts).

  Uses raw SQL with ON CONFLICT for atomic upsert to avoid TOCTOU race conditions.
  """
  @spec upsert_bucket(map()) :: {:ok, TelemetryBucket.t()} | {:error, term()}
  def upsert_bucket(attrs) do
    # Validate event_name to prevent atom exhaustion attacks
    unless is_binary(attrs.event_name) and String.match?(attrs.event_name, ~r/^[a-z0-9._]+$/) do
      raise ArgumentError, "Invalid event_name format: #{inspect(attrs.event_name)}"
    end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    sql = """
    INSERT INTO telemetry_buckets (
      event_name, bucket_type, bucket_start, count,
      sum_values, min_values, max_values, metadata_counts, inserted_at
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
    ON CONFLICT (event_name, bucket_type, bucket_start) DO UPDATE SET
      count = telemetry_buckets.count + EXCLUDED.count,
      sum_values = jsonb_merge_add(telemetry_buckets.sum_values, EXCLUDED.sum_values),
      min_values = jsonb_merge_min(telemetry_buckets.min_values, EXCLUDED.min_values),
      max_values = jsonb_merge_max(telemetry_buckets.max_values, EXCLUDED.max_values),
      metadata_counts = jsonb_merge_add(telemetry_buckets.metadata_counts, EXCLUDED.metadata_counts)
    RETURNING *
    """

    case Repo.query(sql, [
           attrs.event_name,
           to_string(attrs.bucket_type),
           attrs.bucket_start,
           Map.get(attrs, :count, 0),
           Map.get(attrs, :sum_values, %{}),
           Map.get(attrs, :min_values, %{}),
           Map.get(attrs, :max_values, %{}),
           Map.get(attrs, :metadata_counts, %{}),
           now
         ]) do
      {:ok, %{rows: [row], columns: columns}} ->
        # Convert string column names to atoms for Repo.load
        data =
          columns
          |> Enum.zip(row)
          |> Enum.into(%{}, fn {col, val} -> {String.to_existing_atom(col), val} end)

        bucket = Repo.load(TelemetryBucket, data)
        {:ok, bucket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Delete events older than the given cutoff.
  """
  @spec purge_events_before(DateTime.t()) :: {non_neg_integer(), nil}
  def purge_events_before(cutoff) do
    TelemetryEvent
    |> where([e], e.occurred_at < ^cutoff)
    |> Repo.delete_all()
  end

  @doc """
  Delete buckets older than the given cutoff for a bucket type.
  """
  @spec purge_buckets_before(atom(), DateTime.t()) :: {non_neg_integer(), nil}
  def purge_buckets_before(bucket_type, cutoff) do
    TelemetryBucket
    |> where([b], b.bucket_type == ^bucket_type)
    |> where([b], b.bucket_start < ^cutoff)
    |> Repo.delete_all()
  end
end
