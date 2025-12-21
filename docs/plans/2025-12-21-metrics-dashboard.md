# Telemetry Metrics Dashboard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Store telemetry events in Postgres with rollup aggregation and visualize via Chart.js in a tabbed Phoenix LiveView dashboard.

**Architecture:** Telemetry events are captured by a buffered GenServer that batch-inserts to Postgres every 5 seconds. A RollupScheduler aggregates raw events into minute/hour/day buckets on timers. A LiveView dashboard queries these tables and renders Chart.js visualizations with auto-refresh.

**Tech Stack:** Elixir/Phoenix, Ecto, PostgreSQL, Chart.js (via CDN), Phoenix LiveView hooks

---

## Task 1: Create Telemetry Event Schema

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/telemetry_event.ex`
- Test: `apps/bezgelor_db/test/schema/telemetry_event_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_db/test/schema/telemetry_event_test.exs`:

```elixir
defmodule BezgelorDb.Schema.TelemetryEventTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Schema.TelemetryEvent

  describe "changeset/2" do
    test "valid attributes create valid changeset" do
      attrs = %{
        event_name: "bezgelor.auth.login_complete",
        measurements: %{duration_ms: 150},
        metadata: %{account_id: 1, success: true},
        occurred_at: DateTime.utc_now()
      }

      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, attrs)
      assert changeset.valid?
    end

    test "requires event_name" do
      changeset = TelemetryEvent.changeset(%TelemetryEvent{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_name
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/schema/telemetry_event_test.exs -v`

Expected: FAIL with "module TelemetryEvent is not available"

**Step 3: Write minimal implementation**

Create `apps/bezgelor_db/lib/bezgelor_db/schema/telemetry_event.ex`:

```elixir
defmodule BezgelorDb.Schema.TelemetryEvent do
  @moduledoc """
  Raw telemetry event storage.

  Stores individual telemetry events for up to 48 hours before rollup.
  Events are batch-inserted by TelemetryCollector every few seconds.

  ## Fields

  - `event_name` - Dotted event name (e.g., "bezgelor.auth.login_complete")
  - `measurements` - JSON map of numeric measurements
  - `metadata` - JSON map of event context/tags
  - `occurred_at` - When the event was emitted
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          event_name: String.t() | nil,
          measurements: map() | nil,
          metadata: map() | nil,
          occurred_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "telemetry_events" do
    field(:event_name, :string)
    field(:measurements, :map)
    field(:metadata, :map)
    field(:occurred_at, :utc_datetime_usec)

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc """
  Changeset for creating a telemetry event.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_name, :measurements, :metadata, :occurred_at])
    |> validate_required([:event_name, :occurred_at])
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/schema/telemetry_event_test.exs -v`

Expected: PASS (2 tests)

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/telemetry_event.ex apps/bezgelor_db/test/schema/telemetry_event_test.exs
git commit -m "feat(db): add telemetry_event schema for raw event storage"
```

---

## Task 2: Create Telemetry Bucket Schemas

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/schema/telemetry_bucket.ex`
- Test: `apps/bezgelor_db/test/schema/telemetry_bucket_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_db/test/schema/telemetry_bucket_test.exs`:

```elixir
defmodule BezgelorDb.Schema.TelemetryBucketTest do
  use ExUnit.Case, async: true

  alias BezgelorDb.Schema.TelemetryBucket

  describe "changeset/2" do
    test "valid minute bucket" do
      attrs = %{
        event_name: "bezgelor.auth.login_complete",
        bucket_type: :minute,
        bucket_start: ~U[2025-12-21 14:32:00Z],
        count: 23,
        sum_values: %{duration_ms: 3450},
        min_values: %{duration_ms: 50},
        max_values: %{duration_ms: 500},
        metadata_counts: %{"success:true" => 20, "success:false" => 3}
      }

      changeset = TelemetryBucket.changeset(%TelemetryBucket{}, attrs)
      assert changeset.valid?
    end

    test "requires bucket_type" do
      attrs = %{event_name: "test", bucket_start: DateTime.utc_now(), count: 1}
      changeset = TelemetryBucket.changeset(%TelemetryBucket{}, attrs)
      refute changeset.valid?
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/schema/telemetry_bucket_test.exs -v`

Expected: FAIL with "module TelemetryBucket is not available"

**Step 3: Write minimal implementation**

Create `apps/bezgelor_db/lib/bezgelor_db/schema/telemetry_bucket.ex`:

```elixir
defmodule BezgelorDb.Schema.TelemetryBucket do
  @moduledoc """
  Aggregated telemetry bucket storage.

  Stores pre-aggregated telemetry data at minute, hour, and day granularities.
  Buckets are created by RollupScheduler from raw events.

  ## Bucket Types

  - `:minute` - 1-minute buckets, retained 14 days
  - `:hour` - 1-hour buckets, retained 90 days
  - `:day` - 1-day buckets, retained 1 year

  ## Fields

  - `event_name` - Dotted event name
  - `bucket_type` - Granularity (:minute, :hour, :day)
  - `bucket_start` - Start timestamp of this bucket
  - `count` - Number of events in bucket
  - `sum_values` - Sum of each measurement
  - `min_values` - Min of each measurement
  - `max_values` - Max of each measurement
  - `metadata_counts` - Counts per metadata combination
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type bucket_type :: :minute | :hour | :day

  @type t :: %__MODULE__{
          id: integer() | nil,
          event_name: String.t() | nil,
          bucket_type: bucket_type() | nil,
          bucket_start: DateTime.t() | nil,
          count: integer() | nil,
          sum_values: map() | nil,
          min_values: map() | nil,
          max_values: map() | nil,
          metadata_counts: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "telemetry_buckets" do
    field(:event_name, :string)
    field(:bucket_type, Ecto.Enum, values: [:minute, :hour, :day])
    field(:bucket_start, :utc_datetime)
    field(:count, :integer, default: 0)
    field(:sum_values, :map, default: %{})
    field(:min_values, :map, default: %{})
    field(:max_values, :map, default: %{})
    field(:metadata_counts, :map, default: %{})

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc """
  Changeset for creating a telemetry bucket.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, [
      :event_name,
      :bucket_type,
      :bucket_start,
      :count,
      :sum_values,
      :min_values,
      :max_values,
      :metadata_counts
    ])
    |> validate_required([:event_name, :bucket_type, :bucket_start, :count])
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/schema/telemetry_bucket_test.exs -v`

Expected: PASS (2 tests)

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/schema/telemetry_bucket.ex apps/bezgelor_db/test/schema/telemetry_bucket_test.exs
git commit -m "feat(db): add telemetry_bucket schema for aggregated metrics"
```

---

## Task 3: Create Database Migration

**Files:**
- Create: `apps/bezgelor_db/priv/repo/migrations/TIMESTAMP_create_telemetry_tables.exs`

**Step 1: Generate migration file**

Run: `cd apps/bezgelor_db && mix ecto.gen.migration create_telemetry_tables`

Note the generated filename timestamp.

**Step 2: Write the migration**

Edit the generated file:

```elixir
defmodule BezgelorDb.Repo.Migrations.CreateTelemetryTables do
  use Ecto.Migration

  def change do
    # Raw telemetry events (retained 48 hours)
    create table(:telemetry_events) do
      add :event_name, :string, null: false
      add :measurements, :map, default: %{}
      add :metadata, :map, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create index(:telemetry_events, [:event_name])
    create index(:telemetry_events, [:occurred_at])
    create index(:telemetry_events, [:event_name, :occurred_at])

    # Aggregated buckets (minute/hour/day)
    create table(:telemetry_buckets) do
      add :event_name, :string, null: false
      add :bucket_type, :string, null: false
      add :bucket_start, :utc_datetime, null: false
      add :count, :integer, null: false, default: 0
      add :sum_values, :map, default: %{}
      add :min_values, :map, default: %{}
      add :max_values, :map, default: %{}
      add :metadata_counts, :map, default: %{}

      timestamps(updated_at: false, type: :utc_datetime)
    end

    # Unique constraint for upserts
    create unique_index(:telemetry_buckets, [:event_name, :bucket_type, :bucket_start])
    create index(:telemetry_buckets, [:bucket_type, :bucket_start])
    create index(:telemetry_buckets, [:event_name, :bucket_type])
  end
end
```

**Step 3: Run migration**

Run: `mix ecto.migrate`

Expected: Migration completes successfully

**Step 4: Verify tables exist**

Run: `mix ecto.migrations`

Expected: Shows migration as "up"

**Step 5: Commit**

```bash
git add apps/bezgelor_db/priv/repo/migrations/*_create_telemetry_tables.exs
git commit -m "feat(db): add telemetry_events and telemetry_buckets tables"
```

---

## Task 4: Create Metrics Context Module

**Files:**
- Create: `apps/bezgelor_db/lib/bezgelor_db/metrics.ex`
- Test: `apps/bezgelor_db/test/metrics_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_db/test/metrics_test.exs`:

```elixir
defmodule BezgelorDb.MetricsTest do
  use BezgelorDb.DataCase, async: false

  alias BezgelorDb.Metrics

  @moduletag :database

  describe "insert_events/1" do
    test "batch inserts multiple events" do
      events = [
        %{
          event_name: "bezgelor.auth.login_complete",
          measurements: %{duration_ms: 100},
          metadata: %{success: true},
          occurred_at: DateTime.utc_now()
        },
        %{
          event_name: "bezgelor.auth.login_complete",
          measurements: %{duration_ms: 200},
          metadata: %{success: false},
          occurred_at: DateTime.utc_now()
        }
      ]

      assert {:ok, 2} = Metrics.insert_events(events)
    end
  end

  describe "query_events/3" do
    test "queries events by name and time range" do
      now = DateTime.utc_now()

      Metrics.insert_events([
        %{
          event_name: "test.event",
          measurements: %{value: 1},
          metadata: %{},
          occurred_at: now
        }
      ])

      from = DateTime.add(now, -60, :second)
      to = DateTime.add(now, 60, :second)

      events = Metrics.query_events("test.event", from, to)
      assert length(events) == 1
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_db/test/metrics_test.exs --include database -v`

Expected: FAIL with "module Metrics is not available"

**Step 3: Write minimal implementation**

Create `apps/bezgelor_db/lib/bezgelor_db/metrics.ex`:

```elixir
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
  """
  @spec upsert_bucket(map()) :: {:ok, TelemetryBucket.t()} | {:error, Ecto.Changeset.t()}
  def upsert_bucket(attrs) do
    %TelemetryBucket{}
    |> TelemetryBucket.changeset(attrs)
    |> Repo.insert(
      on_conflict: [
        inc: [count: attrs.count],
        set: [
          sum_values: attrs.sum_values,
          min_values: attrs.min_values,
          max_values: attrs.max_values,
          metadata_counts: attrs.metadata_counts
        ]
      ],
      conflict_target: [:event_name, :bucket_type, :bucket_start]
    )
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
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_db/test/metrics_test.exs --include database -v`

Expected: PASS (2 tests)

**Step 5: Commit**

```bash
git add apps/bezgelor_db/lib/bezgelor_db/metrics.ex apps/bezgelor_db/test/metrics_test.exs
git commit -m "feat(db): add Metrics context for telemetry storage and queries"
```

---

## Task 5: Create TelemetryCollector GenServer

**Files:**
- Create: `apps/bezgelor_portal/lib/bezgelor_portal/telemetry_collector.ex`
- Test: `apps/bezgelor_portal/test/telemetry_collector_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_portal/test/telemetry_collector_test.exs`:

```elixir
defmodule BezgelorPortal.TelemetryCollectorTest do
  use ExUnit.Case, async: false

  alias BezgelorPortal.TelemetryCollector

  describe "handle_event/4" do
    test "buffers events" do
      # Start collector for test
      {:ok, pid} = TelemetryCollector.start_link(flush_interval: :infinity)

      TelemetryCollector.handle_event(
        [:test, :event],
        %{value: 42},
        %{tag: "test"},
        %{collector: pid}
      )

      state = :sys.get_state(pid)
      assert length(state.buffer) == 1

      GenServer.stop(pid)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_portal/test/telemetry_collector_test.exs -v`

Expected: FAIL with "module TelemetryCollector is not available"

**Step 3: Write minimal implementation**

Create `apps/bezgelor_portal/lib/bezgelor_portal/telemetry_collector.ex`:

```elixir
defmodule BezgelorPortal.TelemetryCollector do
  @moduledoc """
  Collects telemetry events and batch-inserts to database.

  Attaches to telemetry events, buffers them in memory, and flushes
  to PostgreSQL every few seconds in batched inserts.

  ## Configuration

  - `:flush_interval` - Milliseconds between flushes (default: 5000)
  - `:max_buffer_size` - Force flush at this size (default: 1000)
  """

  use GenServer
  require Logger

  alias BezgelorDb.Metrics

  @default_flush_interval 5_000
  @default_max_buffer_size 1_000

  # Events to capture
  @tracked_events [
    [:bezgelor, :auth, :login_complete],
    [:bezgelor, :realm, :session_start],
    [:bezgelor, :world, :player_entered],
    [:bezgelor, :combat, :damage],
    [:bezgelor, :quest, :accepted],
    [:bezgelor, :quest, :completed],
    [:bezgelor, :quest, :abandoned],
    [:bezgelor, :creature, :killed],
    [:bezgelor, :server, :players],
    [:bezgelor, :server, :creatures],
    [:bezgelor, :server, :zones]
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    flush_interval = Keyword.get(opts, :flush_interval, @default_flush_interval)
    max_buffer_size = Keyword.get(opts, :max_buffer_size, @default_max_buffer_size)

    # Attach to telemetry events
    attach_handlers()

    # Schedule periodic flush (unless :infinity for testing)
    if flush_interval != :infinity do
      schedule_flush(flush_interval)
    end

    {:ok,
     %{
       buffer: [],
       flush_interval: flush_interval,
       max_buffer_size: max_buffer_size
     }}
  end

  @doc """
  Telemetry handler callback. Sends event to collector process.
  """
  def handle_event(event_name, measurements, metadata, config) do
    collector = Map.get(config, :collector, __MODULE__)

    GenServer.cast(collector, {:event, event_name, measurements, metadata, DateTime.utc_now()})
  end

  @impl true
  def handle_cast({:event, event_name, measurements, metadata, occurred_at}, state) do
    event = %{
      event_name: Enum.join(event_name, "."),
      measurements: measurements,
      metadata: metadata,
      occurred_at: occurred_at
    }

    new_buffer = [event | state.buffer]

    # Force flush if buffer is full
    if length(new_buffer) >= state.max_buffer_size do
      flush_buffer(new_buffer)
      {:noreply, %{state | buffer: []}}
    else
      {:noreply, %{state | buffer: new_buffer}}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    if state.buffer != [] do
      flush_buffer(state.buffer)
    end

    schedule_flush(state.flush_interval)
    {:noreply, %{state | buffer: []}}
  end

  defp attach_handlers do
    Enum.each(@tracked_events, fn event ->
      handler_id = "telemetry_collector_#{Enum.join(event, "_")}"

      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_event/4,
        %{collector: self()}
      )
    end)
  end

  defp schedule_flush(interval) do
    Process.send_after(self(), :flush, interval)
  end

  defp flush_buffer(buffer) do
    case Metrics.insert_events(buffer) do
      {:ok, count} ->
        Logger.debug("TelemetryCollector flushed #{count} events")

      {:error, reason} ->
        Logger.error("TelemetryCollector flush failed: #{inspect(reason)}")
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_portal/test/telemetry_collector_test.exs -v`

Expected: PASS (1 test)

**Step 5: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal/telemetry_collector.ex apps/bezgelor_portal/test/telemetry_collector_test.exs
git commit -m "feat(portal): add TelemetryCollector for buffered event capture"
```

---

## Task 6: Create RollupScheduler GenServer

**Files:**
- Create: `apps/bezgelor_portal/lib/bezgelor_portal/rollup_scheduler.ex`
- Test: `apps/bezgelor_portal/test/rollup_scheduler_test.exs`

**Step 1: Write the failing test**

Create `apps/bezgelor_portal/test/rollup_scheduler_test.exs`:

```elixir
defmodule BezgelorPortal.RollupSchedulerTest do
  use BezgelorDb.DataCase, async: false

  alias BezgelorPortal.RollupScheduler
  alias BezgelorDb.Metrics

  @moduletag :database

  describe "rollup_minute/0" do
    test "aggregates events into minute buckets" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      bucket_start = now |> Map.put(:second, 0)

      # Insert test events
      Metrics.insert_events([
        %{
          event_name: "test.event",
          measurements: %{"value" => 10},
          metadata: %{"tag" => "a"},
          occurred_at: now
        },
        %{
          event_name: "test.event",
          measurements: %{"value" => 20},
          metadata: %{"tag" => "a"},
          occurred_at: now
        }
      ])

      # Run rollup
      RollupScheduler.rollup_minute()

      # Check bucket was created
      buckets = Metrics.query_buckets("test.event", :minute, bucket_start, now)
      assert length(buckets) == 1

      bucket = hd(buckets)
      assert bucket.count == 2
      assert bucket.sum_values["value"] == 30
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test apps/bezgelor_portal/test/rollup_scheduler_test.exs --include database -v`

Expected: FAIL with "module RollupScheduler is not available"

**Step 3: Write minimal implementation**

Create `apps/bezgelor_portal/lib/bezgelor_portal/rollup_scheduler.ex`:

```elixir
defmodule BezgelorPortal.RollupScheduler do
  @moduledoc """
  Periodically aggregates raw telemetry events into buckets.

  ## Schedule

  - Every 1 minute: Aggregate raw events into minute buckets
  - Every 1 hour: Aggregate minute buckets into hour buckets
  - Every 1 day: Aggregate hour buckets into day buckets, purge old data

  ## Retention

  - Raw events: 48 hours
  - Minute buckets: 14 days
  - Hour buckets: 90 days
  - Day buckets: 1 year
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{TelemetryEvent, TelemetryBucket}
  alias BezgelorDb.Metrics

  @minute_interval :timer.minutes(1)
  @hour_interval :timer.hours(1)
  @day_interval :timer.hours(24)

  # Retention periods
  @raw_retention_hours 48
  @minute_retention_days 14
  @hour_retention_days 90
  @day_retention_days 365

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(_opts) do
    schedule_minute_rollup()
    schedule_hour_rollup()
    schedule_day_rollup()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:minute_rollup, state) do
    rollup_minute()
    schedule_minute_rollup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:hour_rollup, state) do
    rollup_hour()
    schedule_hour_rollup()
    {:noreply, state}
  end

  @impl true
  def handle_info(:day_rollup, state) do
    rollup_day()
    purge_old_data()
    schedule_day_rollup()
    {:noreply, state}
  end

  @doc """
  Aggregate raw events from the last minute into minute buckets.
  """
  def rollup_minute do
    now = DateTime.utc_now()
    bucket_start = now |> DateTime.truncate(:second) |> Map.put(:second, 0)
    from = DateTime.add(bucket_start, -60, :second)

    aggregate_events_to_buckets(from, bucket_start, :minute)
  end

  @doc """
  Aggregate minute buckets from the last hour into hour buckets.
  """
  def rollup_hour do
    now = DateTime.utc_now()
    bucket_start = now |> DateTime.truncate(:second) |> Map.put(:second, 0) |> Map.put(:minute, 0)
    from = DateTime.add(bucket_start, -3600, :second)

    aggregate_buckets(:minute, from, bucket_start, :hour, bucket_start)
  end

  @doc """
  Aggregate hour buckets from the last day into day buckets.
  """
  def rollup_day do
    now = DateTime.utc_now()
    today = DateTime.to_date(now)
    bucket_start = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    from = DateTime.add(bucket_start, -86400, :second)

    aggregate_buckets(:hour, from, bucket_start, :day, bucket_start)
  end

  defp aggregate_events_to_buckets(from, to, bucket_type) do
    # Query events grouped by name and aggregate
    query =
      from(e in TelemetryEvent,
        where: e.occurred_at >= ^from and e.occurred_at < ^to,
        group_by: e.event_name,
        select: %{
          event_name: e.event_name,
          count: count(e.id),
          events: fragment("array_agg(row_to_json(?))", e)
        }
      )

    bucket_start_truncated =
      from |> DateTime.truncate(:second) |> Map.put(:second, 0)

    Repo.all(query)
    |> Enum.each(fn row ->
      # Parse aggregated events to compute min/max/sum
      {sum_values, min_values, max_values, metadata_counts} =
        compute_aggregates(row.events)

      Metrics.upsert_bucket(%{
        event_name: row.event_name,
        bucket_type: bucket_type,
        bucket_start: bucket_start_truncated,
        count: row.count,
        sum_values: sum_values,
        min_values: min_values,
        max_values: max_values,
        metadata_counts: metadata_counts
      })
    end)

    Logger.debug("RollupScheduler: aggregated #{bucket_type} buckets from #{from} to #{to}")
  end

  defp aggregate_buckets(source_type, from, to, target_type, target_start) do
    query =
      from(b in TelemetryBucket,
        where: b.bucket_type == ^source_type,
        where: b.bucket_start >= ^from and b.bucket_start < ^to,
        group_by: b.event_name,
        select: %{
          event_name: b.event_name,
          count: sum(b.count),
          sum_values: fragment("jsonb_object_agg(key, COALESCE((? ->> key)::numeric, 0)) FROM jsonb_each_text(?)", b.sum_values, b.sum_values)
        }
      )

    # Simplified: just sum counts for now
    TelemetryBucket
    |> where([b], b.bucket_type == ^source_type)
    |> where([b], b.bucket_start >= ^from and b.bucket_start < ^to)
    |> Repo.all()
    |> Enum.group_by(& &1.event_name)
    |> Enum.each(fn {event_name, buckets} ->
      total_count = Enum.sum(Enum.map(buckets, & &1.count))

      sum_values = merge_sum_values(Enum.map(buckets, & &1.sum_values))
      min_values = merge_min_values(Enum.map(buckets, & &1.min_values))
      max_values = merge_max_values(Enum.map(buckets, & &1.max_values))
      metadata_counts = merge_metadata_counts(Enum.map(buckets, & &1.metadata_counts))

      Metrics.upsert_bucket(%{
        event_name: event_name,
        bucket_type: target_type,
        bucket_start: target_start,
        count: total_count,
        sum_values: sum_values,
        min_values: min_values,
        max_values: max_values,
        metadata_counts: metadata_counts
      })
    end)

    Logger.debug("RollupScheduler: rolled up #{source_type} to #{target_type}")
  end

  defp purge_old_data do
    now = DateTime.utc_now()

    # Purge raw events older than 48 hours
    raw_cutoff = DateTime.add(now, -@raw_retention_hours, :hour)
    {raw_count, _} = Metrics.purge_events_before(raw_cutoff)

    # Purge minute buckets older than 14 days
    minute_cutoff = DateTime.add(now, -@minute_retention_days, :day)
    {minute_count, _} = Metrics.purge_buckets_before(:minute, minute_cutoff)

    # Purge hour buckets older than 90 days
    hour_cutoff = DateTime.add(now, -@hour_retention_days, :day)
    {hour_count, _} = Metrics.purge_buckets_before(:hour, hour_cutoff)

    # Purge day buckets older than 1 year
    day_cutoff = DateTime.add(now, -@day_retention_days, :day)
    {day_count, _} = Metrics.purge_buckets_before(:day, day_cutoff)

    Logger.info(
      "RollupScheduler purge: #{raw_count} events, #{minute_count} minute, #{hour_count} hour, #{day_count} day buckets"
    )
  end

  defp compute_aggregates(events) when is_list(events) do
    Enum.reduce(events, {%{}, %{}, %{}, %{}}, fn event_json, {sum, min, max, meta} ->
      event = if is_binary(event_json), do: Jason.decode!(event_json), else: event_json
      measurements = event["measurements"] || %{}
      metadata = event["metadata"] || %{}

      new_sum = merge_sum(sum, measurements)
      new_min = merge_min(min, measurements)
      new_max = merge_max(max, measurements)
      meta_key = metadata |> Enum.sort() |> Enum.map(fn {k, v} -> "#{k}:#{v}" end) |> Enum.join(",")
      new_meta = Map.update(meta, meta_key, 1, &(&1 + 1))

      {new_sum, new_min, new_max, new_meta}
    end)
  end

  defp merge_sum(acc, measurements) do
    Enum.reduce(measurements, acc, fn {k, v}, a ->
      Map.update(a, k, v, &(&1 + v))
    end)
  end

  defp merge_min(acc, measurements) do
    Enum.reduce(measurements, acc, fn {k, v}, a ->
      Map.update(a, k, v, &min(&1, v))
    end)
  end

  defp merge_max(acc, measurements) do
    Enum.reduce(measurements, acc, fn {k, v}, a ->
      Map.update(a, k, v, &max(&1, v))
    end)
  end

  defp merge_sum_values(list), do: Enum.reduce(list, %{}, &merge_sum(&2, &1 || %{}))
  defp merge_min_values(list), do: Enum.reduce(list, %{}, &merge_min(&2, &1 || %{}))
  defp merge_max_values(list), do: Enum.reduce(list, %{}, &merge_max(&2, &1 || %{}))

  defp merge_metadata_counts(list) do
    Enum.reduce(list, %{}, fn counts, acc ->
      Enum.reduce(counts || %{}, acc, fn {k, v}, a ->
        Map.update(a, k, v, &(&1 + v))
      end)
    end)
  end

  defp schedule_minute_rollup, do: Process.send_after(self(), :minute_rollup, @minute_interval)
  defp schedule_hour_rollup, do: Process.send_after(self(), :hour_rollup, @hour_interval)
  defp schedule_day_rollup, do: Process.send_after(self(), :day_rollup, @day_interval)
end
```

**Step 4: Run test to verify it passes**

Run: `mix test apps/bezgelor_portal/test/rollup_scheduler_test.exs --include database -v`

Expected: PASS (1 test)

**Step 5: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal/rollup_scheduler.ex apps/bezgelor_portal/test/rollup_scheduler_test.exs
git commit -m "feat(portal): add RollupScheduler for telemetry aggregation"
```

---

## Task 7: Add Collectors to Application Supervisor

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal/application.ex`

**Step 1: Read current file**

Already read above.

**Step 2: Add children to supervisor**

Edit `apps/bezgelor_portal/lib/bezgelor_portal/application.ex`:

```elixir
defmodule BezgelorPortal.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BezgelorPortalWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:bezgelor_portal, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BezgelorPortal.PubSub},
      # Rate limiting for auth actions
      {BezgelorPortal.Hammer, clean_period: :timer.minutes(10)},
      # Encryption vault for TOTP secrets
      BezgelorPortal.Vault,
      # Log buffer for admin log viewer
      BezgelorPortal.LogBuffer,
      # Telemetry metrics collection and rollup
      BezgelorPortal.TelemetryCollector,
      BezgelorPortal.RollupScheduler,
      # Start to serve requests, typically the last entry
      BezgelorPortalWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: BezgelorPortal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    BezgelorPortalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

**Step 3: Verify application starts**

Run: `mix compile && mix run -e "IO.puts(\"OK\")"`

Expected: Compiles and prints "OK"

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal/application.ex
git commit -m "feat(portal): add TelemetryCollector and RollupScheduler to supervisor"
```

---

## Task 8: Create Chart.js Hook

**Files:**
- Create: `apps/bezgelor_portal/assets/js/metrics_chart.js`
- Modify: `apps/bezgelor_portal/assets/js/app.js`

**Step 1: Create the Chart.js hook**

Create `apps/bezgelor_portal/assets/js/metrics_chart.js`:

```javascript
// Chart.js hook for Phoenix LiveView
// Uses Chart.js from CDN (loaded in layout)

const MetricsChart = {
  mounted() {
    this.chart = null
    this.initChart()

    this.handleEvent("update_chart", (data) => {
      this.updateChart(data)
    })
  },

  initChart() {
    const ctx = this.el.getContext("2d")
    const chartType = this.el.dataset.chartType || "line"
    const chartTitle = this.el.dataset.chartTitle || ""

    this.chart = new Chart(ctx, {
      type: chartType,
      data: {
        labels: [],
        datasets: []
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: "top"
          },
          title: {
            display: !!chartTitle,
            text: chartTitle
          }
        },
        scales: {
          x: {
            type: "time",
            time: {
              unit: "minute",
              displayFormats: {
                minute: "HH:mm",
                hour: "HH:mm",
                day: "MMM d"
              }
            }
          },
          y: {
            beginAtZero: true
          }
        }
      }
    })
  },

  updateChart(data) {
    if (!this.chart) return

    // Update time unit based on data range
    if (data.timeUnit) {
      this.chart.options.scales.x.time.unit = data.timeUnit
    }

    this.chart.data.labels = data.labels || []
    this.chart.data.datasets = data.datasets || []
    this.chart.update("none") // No animation for live updates
  },

  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}

export default MetricsChart
```

**Step 2: Register hook in app.js**

Edit `apps/bezgelor_portal/assets/js/app.js`, add near the top after imports:

```javascript
import MetricsChart from "./metrics_chart"

// Add to Hooks object (find existing Hooks = {} or create one)
let Hooks = {}
Hooks.MetricsChart = MetricsChart

// Pass to LiveSocket
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  // ... existing params
})
```

**Step 3: Add Chart.js CDN to layout**

Edit `apps/bezgelor_portal/lib/bezgelor_portal_web/components/layouts/root.html.heex`, add before closing `</head>`:

```html
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3.0.0/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
```

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/assets/js/metrics_chart.js apps/bezgelor_portal/assets/js/app.js apps/bezgelor_portal/lib/bezgelor_portal_web/components/layouts/root.html.heex
git commit -m "feat(portal): add Chart.js hook for metrics visualization"
```

---

## Task 9: Create MetricsDashboardLive - Server Tab

**Files:**
- Create: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/metrics_dashboard_live.ex`

**Step 1: Create the LiveView with Server tab**

Create `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/metrics_dashboard_live.ex`:

```elixir
defmodule BezgelorPortalWeb.Admin.MetricsDashboardLive do
  @moduledoc """
  Admin LiveView for historical telemetry metrics dashboard.

  Displays Chart.js visualizations of telemetry data stored in PostgreSQL.
  Supports time range selection and auto-refresh.
  """

  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Metrics

  @refresh_interval 10_000

  @time_ranges %{
    "1h" => 1,
    "6h" => 6,
    "24h" => 24,
    "7d" => 24 * 7,
    "30d" => 24 * 30
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Metrics Dashboard",
       active_tab: :server,
       time_range: "1h",
       custom_from: nil,
       custom_to: nil
     )
     |> load_chart_data(), layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, load_chart_data(socket)}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(active_tab: String.to_existing_atom(tab))
     |> load_chart_data()}
  end

  @impl true
  def handle_event("change_time_range", %{"range" => range}, socket) do
    {:noreply,
     socket
     |> assign(time_range: range, custom_from: nil, custom_to: nil)
     |> load_chart_data()}
  end

  @impl true
  def handle_event("custom_range", %{"from" => from, "to" => to}, socket) do
    {:noreply,
     socket
     |> assign(time_range: "custom", custom_from: from, custom_to: to)
     |> load_chart_data()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Metrics Dashboard</h1>
          <p class="text-base-content/70">Historical telemetry data visualization</p>
        </div>
        <div class="flex items-center gap-2 text-sm text-base-content/70">
          <span class="loading loading-ring loading-xs"></span>
          <span>Auto-refresh every {div(@refresh_interval, 1000)}s</span>
        </div>
      </div>

      <!-- Time Range Selector -->
      <div class="flex items-center gap-4">
        <div class="join">
          <button
            :for={{label, _} <- @time_ranges}
            type="button"
            class={"join-item btn btn-sm #{if @time_range == label, do: "btn-primary", else: "btn-ghost"}"}
            phx-click="change_time_range"
            phx-value-range={label}
          >
            {label}
          </button>
        </div>
        <div class="flex items-center gap-2">
          <input
            type="datetime-local"
            name="from"
            class="input input-sm input-bordered"
            value={@custom_from}
            phx-blur="custom_range"
          />
          <span>to</span>
          <input
            type="datetime-local"
            name="to"
            class="input input-sm input-bordered"
            value={@custom_to}
            phx-blur="custom_range"
          />
        </div>
      </div>

      <!-- Tabs -->
      <div role="tablist" class="tabs tabs-boxed bg-base-100 p-1 w-fit">
        <button
          :for={tab <- [:server, :auth, :gameplay, :combat]}
          type="button"
          role="tab"
          class={"tab #{if @active_tab == tab, do: "tab-active"}"}
          phx-click="change_tab"
          phx-value-tab={tab}
        >
          {tab_label(tab)}
        </button>
      </div>

      <!-- Tab Content -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <%= case @active_tab do %>
          <% :server -> %>
            <.chart_card title="Players Online" id="players-chart" chart_data={@players_data} />
            <.chart_card title="Creatures Spawned" id="creatures-chart" chart_data={@creatures_data} />
            <.chart_card title="Active Zones" id="zones-chart" chart_data={@zones_data} />
          <% :auth -> %>
            <.chart_card title="Login Rate" id="logins-chart" chart_data={@logins_data} />
            <.chart_card
              title="Login Success/Failure"
              id="login-success-chart"
              chart_data={@login_success_data}
              chart_type="bar"
            />
            <.chart_card title="Session Starts" id="sessions-chart" chart_data={@sessions_data} />
          <% :gameplay -> %>
            <.chart_card title="Players Entering World" id="world-entry-chart" chart_data={@world_entry_data} />
            <.chart_card title="Quests Accepted" id="quests-accepted-chart" chart_data={@quests_accepted_data} />
            <.chart_card title="Quests Completed" id="quests-completed-chart" chart_data={@quests_completed_data} />
          <% :combat -> %>
            <.chart_card title="Creatures Killed" id="kills-chart" chart_data={@kills_data} />
            <.chart_card title="XP Awarded" id="xp-chart" chart_data={@xp_data} />
            <.chart_card title="Damage Dealt" id="damage-chart" chart_data={@damage_data} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :id, :string, required: true
  attr :chart_data, :map, required: true
  attr :chart_type, :string, default: "line"

  defp chart_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <h3 class="card-title text-base">{@title}</h3>
        <div class="h-64">
          <canvas
            id={@id}
            phx-hook="MetricsChart"
            phx-update="ignore"
            data-chart-type={@chart_type}
            data-chart-title={@title}
          >
          </canvas>
        </div>
      </div>
    </div>
    """
  end

  defp tab_label(:server), do: "Server"
  defp tab_label(:auth), do: "Auth"
  defp tab_label(:gameplay), do: "Gameplay"
  defp tab_label(:combat), do: "Combat"

  defp load_chart_data(socket) do
    {from, to, bucket_type, time_unit} = get_time_range(socket.assigns)

    socket
    |> load_server_data(from, to, bucket_type, time_unit)
    |> load_auth_data(from, to, bucket_type, time_unit)
    |> load_gameplay_data(from, to, bucket_type, time_unit)
    |> load_combat_data(from, to, bucket_type, time_unit)
    |> push_chart_updates()
  end

  defp get_time_range(assigns) do
    now = DateTime.utc_now()

    {from, to} =
      case assigns.time_range do
        "custom" ->
          parse_custom_range(assigns.custom_from, assigns.custom_to, now)

        range ->
          hours = Map.get(@time_ranges, range, 1)
          {DateTime.add(now, -hours, :hour), now}
      end

    # Determine bucket type and chart time unit based on range
    hours_diff = DateTime.diff(to, from, :hour)

    {bucket_type, time_unit} =
      cond do
        hours_diff <= 2 -> {:minute, "minute"}
        hours_diff <= 48 -> {:minute, "hour"}
        hours_diff <= 24 * 14 -> {:hour, "hour"}
        true -> {:day, "day"}
      end

    {from, to, bucket_type, time_unit}
  end

  defp parse_custom_range(nil, _, now), do: {DateTime.add(now, -1, :hour), now}
  defp parse_custom_range(_, nil, now), do: {DateTime.add(now, -1, :hour), now}

  defp parse_custom_range(from_str, to_str, now) do
    with {:ok, from} <- NaiveDateTime.from_iso8601(from_str),
         {:ok, to} <- NaiveDateTime.from_iso8601(to_str) do
      {DateTime.from_naive!(from, "Etc/UTC"), DateTime.from_naive!(to, "Etc/UTC")}
    else
      _ -> {DateTime.add(now, -1, :hour), now}
    end
  end

  defp load_server_data(socket, from, to, bucket_type, time_unit) do
    players_data = query_metric("bezgelor.server.players", from, to, bucket_type, time_unit, "online")
    creatures_data = query_metric("bezgelor.server.creatures", from, to, bucket_type, time_unit, "spawned")
    zones_data = query_metric("bezgelor.server.zones", from, to, bucket_type, time_unit, "active")

    socket
    |> assign(players_data: players_data)
    |> assign(creatures_data: creatures_data)
    |> assign(zones_data: zones_data)
  end

  defp load_auth_data(socket, from, to, bucket_type, time_unit) do
    logins_data = query_metric_count("bezgelor.auth.login_complete", from, to, bucket_type, time_unit)
    sessions_data = query_metric_count("bezgelor.realm.session_start", from, to, bucket_type, time_unit)

    # Success/failure breakdown
    login_success_data = query_metric_by_metadata("bezgelor.auth.login_complete", from, to, bucket_type, "success")

    socket
    |> assign(logins_data: logins_data)
    |> assign(sessions_data: sessions_data)
    |> assign(login_success_data: login_success_data)
  end

  defp load_gameplay_data(socket, from, to, bucket_type, time_unit) do
    world_entry_data = query_metric_count("bezgelor.world.player_entered", from, to, bucket_type, time_unit)
    quests_accepted_data = query_metric_count("bezgelor.quest.accepted", from, to, bucket_type, time_unit)
    quests_completed_data = query_metric_count("bezgelor.quest.completed", from, to, bucket_type, time_unit)

    socket
    |> assign(world_entry_data: world_entry_data)
    |> assign(quests_accepted_data: quests_accepted_data)
    |> assign(quests_completed_data: quests_completed_data)
  end

  defp load_combat_data(socket, from, to, bucket_type, time_unit) do
    kills_data = query_metric_count("bezgelor.creature.killed", from, to, bucket_type, time_unit)
    xp_data = query_metric("bezgelor.creature.killed", from, to, bucket_type, time_unit, "xp_reward")
    damage_data = query_metric("bezgelor.combat.damage", from, to, bucket_type, time_unit, "damage_amount")

    socket
    |> assign(kills_data: kills_data)
    |> assign(xp_data: xp_data)
    |> assign(damage_data: damage_data)
  end

  defp query_metric(event_name, from, to, bucket_type, time_unit, measurement_key) do
    buckets = Metrics.query_buckets(event_name, bucket_type, from, to)

    labels = Enum.map(buckets, &DateTime.to_iso8601(&1.bucket_start))
    values = Enum.map(buckets, fn b -> get_in(b.sum_values, [measurement_key]) || 0 end)

    %{
      timeUnit: time_unit,
      labels: labels,
      datasets: [
        %{
          label: measurement_key,
          data: values,
          borderColor: "rgb(75, 192, 192)",
          backgroundColor: "rgba(75, 192, 192, 0.2)",
          tension: 0.1
        }
      ]
    }
  end

  defp query_metric_count(event_name, from, to, bucket_type, time_unit) do
    buckets = Metrics.query_buckets(event_name, bucket_type, from, to)

    labels = Enum.map(buckets, &DateTime.to_iso8601(&1.bucket_start))
    values = Enum.map(buckets, & &1.count)

    %{
      timeUnit: time_unit,
      labels: labels,
      datasets: [
        %{
          label: "Count",
          data: values,
          borderColor: "rgb(54, 162, 235)",
          backgroundColor: "rgba(54, 162, 235, 0.2)",
          fill: true
        }
      ]
    }
  end

  defp query_metric_by_metadata(event_name, from, to, bucket_type, key) do
    buckets = Metrics.query_buckets(event_name, bucket_type, from, to)

    # Aggregate metadata counts across all buckets
    totals =
      Enum.reduce(buckets, %{}, fn bucket, acc ->
        Enum.reduce(bucket.metadata_counts || %{}, acc, fn {meta_key, count}, inner_acc ->
          if String.starts_with?(meta_key, "#{key}:") do
            Map.update(inner_acc, meta_key, count, &(&1 + count))
          else
            inner_acc
          end
        end)
      end)

    labels = Map.keys(totals)
    values = Map.values(totals)

    %{
      labels: labels,
      datasets: [
        %{
          label: key,
          data: values,
          backgroundColor: ["rgba(75, 192, 192, 0.6)", "rgba(255, 99, 132, 0.6)"]
        }
      ]
    }
  end

  defp push_chart_updates(socket) do
    # Push updates to all chart hooks
    socket
    |> push_event("update_chart", socket.assigns.players_data)
    |> push_event("update_chart", socket.assigns.creatures_data)
    |> push_event("update_chart", socket.assigns.zones_data)
    |> push_event("update_chart", socket.assigns.logins_data)
    |> push_event("update_chart", socket.assigns.sessions_data)
    |> push_event("update_chart", socket.assigns.login_success_data)
    |> push_event("update_chart", socket.assigns.world_entry_data)
    |> push_event("update_chart", socket.assigns.quests_accepted_data)
    |> push_event("update_chart", socket.assigns.quests_completed_data)
    |> push_event("update_chart", socket.assigns.kills_data)
    |> push_event("update_chart", socket.assigns.xp_data)
    |> push_event("update_chart", socket.assigns.damage_data)
  end

  defp time_ranges, do: @time_ranges
end
```

**Step 2: Verify it compiles**

Run: `mix compile`

Expected: Compiles without errors

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/metrics_dashboard_live.ex
git commit -m "feat(portal): add MetricsDashboardLive with tabbed Chart.js visualization"
```

---

## Task 10: Add Route for Metrics Dashboard

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/router.ex`

**Step 1: Read current router**

Run: Read the router file to find the admin scope.

**Step 2: Add route**

Add inside the admin scope (after other admin routes):

```elixir
live "/metrics", Admin.MetricsDashboardLive, :index
```

**Step 3: Verify route exists**

Run: `mix phx.routes | grep metrics`

Expected: Shows the metrics route

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/router.ex
git commit -m "feat(portal): add /admin/metrics route for dashboard"
```

---

## Task 11: Add Metrics to Admin Sidebar

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/components/layouts.ex`

**Step 1: Find admin sidebar links**

Look for the sidebar section with admin links.

**Step 2: Add Metrics Dashboard link**

Add after Live Dashboard or Analytics:

```elixir
%{href: "/admin/metrics", label: "Metrics", permission: "server.view_logs"}
```

**Step 3: Verify sidebar shows link**

Run: `mix phx.server` and check the admin sidebar

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/components/layouts.ex
git commit -m "feat(portal): add Metrics Dashboard to admin sidebar"
```

---

## Task 12: Fix Chart.js Hook Event Targeting

**Files:**
- Modify: `apps/bezgelor_portal/assets/js/metrics_chart.js`
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/metrics_dashboard_live.ex`

**Step 1: Update hook to use targeted events**

The push_event needs to target specific charts. Update the hook:

```javascript
const MetricsChart = {
  mounted() {
    this.chart = null
    this.chartId = this.el.id
    this.initChart()

    // Listen for events targeted at this specific chart
    this.handleEvent(`update_chart_${this.chartId}`, (data) => {
      this.updateChart(data)
    })
  },
  // ... rest unchanged
}
```

**Step 2: Update LiveView to target specific charts**

Replace `push_chart_updates/1`:

```elixir
defp push_chart_updates(socket) do
  socket
  |> push_event("update_chart_players-chart", socket.assigns.players_data)
  |> push_event("update_chart_creatures-chart", socket.assigns.creatures_data)
  |> push_event("update_chart_zones-chart", socket.assigns.zones_data)
  |> push_event("update_chart_logins-chart", socket.assigns.logins_data)
  |> push_event("update_chart_sessions-chart", socket.assigns.sessions_data)
  |> push_event("update_chart_login-success-chart", socket.assigns.login_success_data)
  |> push_event("update_chart_world-entry-chart", socket.assigns.world_entry_data)
  |> push_event("update_chart_quests-accepted-chart", socket.assigns.quests_accepted_data)
  |> push_event("update_chart_quests-completed-chart", socket.assigns.quests_completed_data)
  |> push_event("update_chart_kills-chart", socket.assigns.kills_data)
  |> push_event("update_chart_xp-chart", socket.assigns.xp_data)
  |> push_event("update_chart_damage-chart", socket.assigns.damage_data)
end
```

**Step 3: Test charts update correctly**

Run: `mix phx.server`, navigate to /admin/metrics, verify charts render

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/assets/js/metrics_chart.js apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/metrics_dashboard_live.ex
git commit -m "fix(portal): target chart updates to specific canvas elements"
```

---

## Task 13: Add Empty State Handling

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/metrics_dashboard_live.ex`

**Step 1: Add empty state check to chart_card**

Update the chart_card component:

```elixir
defp chart_card(assigns) do
  has_data = length(assigns.chart_data[:labels] || []) > 0
  assigns = assign(assigns, :has_data, has_data)

  ~H"""
  <div class="card bg-base-100 shadow">
    <div class="card-body">
      <h3 class="card-title text-base">{@title}</h3>
      <div class="h-64">
        <%= if @has_data do %>
          <canvas
            id={@id}
            phx-hook="MetricsChart"
            phx-update="ignore"
            data-chart-type={@chart_type}
            data-chart-title={@title}
          >
          </canvas>
        <% else %>
          <div class="flex items-center justify-center h-full text-base-content/50">
            <div class="text-center">
              <.icon name="hero-chart-bar" class="size-12 mx-auto mb-2 opacity-50" />
              <p>No data available for this time range</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
  </div>
  """
end
```

**Step 2: Verify empty state displays**

Run: `mix phx.server`, check charts show empty state when no data

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/metrics_dashboard_live.ex
git commit -m "feat(portal): add empty state handling for metrics charts"
```

---

## Task 14: Run Full Test Suite

**Step 1: Run all tests**

Run: `mix test --include database`

Expected: All tests pass

**Step 2: Fix any failures**

If tests fail, address each failure.

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: address test failures"
```

---

## Task 15: Manual Integration Test

**Step 1: Start the server**

Run: `iex -S mix phx.server`

**Step 2: Generate test telemetry events**

In IEx:

```elixir
# Emit some test events
:telemetry.execute([:bezgelor, :auth, :login_complete], %{duration_ms: 150}, %{account_id: 1, success: true})
:telemetry.execute([:bezgelor, :auth, :login_complete], %{duration_ms: 200}, %{account_id: 2, success: false})
:telemetry.execute([:bezgelor, :creature, :killed], %{xp_reward: 500}, %{creature_id: 1, zone_id: 100})

# Wait for flush (5 seconds)
Process.sleep(6000)

# Verify events stored
BezgelorDb.Metrics.query_events("bezgelor.auth.login_complete", DateTime.add(DateTime.utc_now(), -60, :second), DateTime.utc_now())
```

**Step 3: Check dashboard shows data**

Navigate to http://localhost:4000/admin/metrics

Verify:
- Tabs switch correctly
- Time range buttons work
- Charts display data (if events were captured)
- Auto-refresh updates charts

**Step 4: Document any issues found**

Create issues or fix immediately.

---

## Task 16: Final Commit and PR

**Step 1: Review all changes**

Run: `git status` and `git diff --stat main`

**Step 2: Create final commit if needed**

```bash
git add -A
git commit -m "feat(portal): complete telemetry metrics dashboard implementation"
```

**Step 3: Push and create PR**

```bash
git push -u origin feat/metrics-dashboard
gh pr create --title "feat: Add Telemetry Metrics Dashboard" --body "$(cat <<'EOF'
## Summary

- Add PostgreSQL storage for telemetry events with rollup aggregation
- Create TelemetryCollector GenServer for buffered event capture
- Create RollupScheduler for minute/hour/day bucket aggregation
- Implement MetricsDashboardLive with Chart.js visualization
- Support time range selection and auto-refresh

## Features

- **Server tab**: Players online, creatures spawned, active zones
- **Auth tab**: Login rate, success/failure breakdown, session starts
- **Gameplay tab**: World entry, quests accepted/completed
- **Combat tab**: Creatures killed, XP awarded, damage dealt

## Test Plan

- [ ] Verify telemetry events are captured and stored
- [ ] Verify rollups aggregate data correctly
- [ ] Verify charts display historical data
- [ ] Verify time range selection works
- [ ] Verify auto-refresh updates charts

EOF
)"
```

---

Plan complete and saved to `docs/plans/2025-12-21-metrics-dashboard.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**