# Telemetry Metrics Dashboard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

> **Supersedes:** `docs/plans/2025-12-21-livedashboard-telemetry-integration.md` - This plan removes Phoenix LiveDashboard and implements a custom metrics dashboard with persistent storage.

**Goal:** Store telemetry events in Postgres with rollup aggregation and visualize via Chart.js in a tabbed Phoenix LiveView dashboard.

**Architecture:** Telemetry events are captured by a buffered GenServer that batch-inserts to Postgres every 5 seconds. A RollupScheduler aggregates raw events into minute/hour/day buckets on timers. A LiveView dashboard queries these tables and renders Chart.js visualizations with auto-refresh.

**Tech Stack:** Elixir/Phoenix, Ecto, PostgreSQL, Chart.js (bundled via npm/esbuild), Phoenix LiveView hooks

---

## Amendments Summary (Review Findings)

The following issues were identified during plan review and added as `⚠️ AMENDMENT` notes throughout:

| Severity | Task | Issue | Fix |
|----------|------|-------|-----|
| **Critical** | 4 | `upsert_bucket` overwrites instead of merging aggregates | Use `replace_all_except` or raw SQL with proper JSON merge |
| **Critical** | 5 | Telemetry handlers leak on GenServer restart | Add `terminate/2` callback to detach handlers |
| **High** | 6 | `array_agg(row_to_json(e))` loads all events into memory | Use streaming with `Repo.stream/2` |
| **High** | 8 | CDN scripts without SRI hashes | Add `integrity` and `crossorigin` attributes |
| **Medium** | 0 | `require_admin_plug` pipeline becomes orphaned | Remove it or document future use |
| **Medium** | 3 | B-tree indexes inefficient for time-series data | Use BRIN indexes for time columns |
| **Medium** | 4 | No validation on `event_name` (atom exhaustion risk) | Add regex validation |
| **Medium** | 5 | Hardcoded `@tracked_events` list | Make configurable via application env |
| **Medium** | 6 | No initial rollup on startup | Run rollup async in init |
| **Medium** | 9 | `:timer.send_interval` leaks when LiveView dies | Use `Process.send_after` pattern |
| **Medium** | 9 | `String.to_existing_atom/1` doesn't prevent atom exhaustion | Validate against `@valid_tabs` whitelist |
| **Medium** | 9 | `load_chart_data/1` queries all 4 tabs on every refresh | Only load active tab's data |
| **Medium** | 13 | Conditional canvas render prevents hook attachment | Always render canvas with overlay |
| **Low** | 6 | Dead code - unused `query` variable | Remove unreachable code |
| **Low** | 9 | `@time_ranges` map doesn't preserve order | Use keyword list for button order |
| **Low** | 14 | Missing purge test and LiveView test | Add test cases |
| **Medium** | 6 | Rollup window boundaries not aligned to complete intervals | Use last complete interval, not current |
| **Medium** | 5 | Metadata may contain PII/sensitive values | Add whitelist sanitization |
| **High** | 8 | CDN scripts violate bundling best practices | Bundle Chart.js via esbuild instead |
| **Medium** | 9 | HEEx class string interpolation (old style) | Use list syntax for classes |
| **Low** | 9 | push_event called when disconnected | Gate with `connected?(socket)` |
| **Critical** | 6 | Rollup test uses wrong time window | Test events must be in PREVIOUS minute |
| **Critical** | 5 | Metadata key type mismatch (atom vs string) | Handle both atom and string keys |
| **Critical** | 4 | upsert still not idempotent with replace_all_except | Use fetch-then-merge pattern |
| **High** | 12 | Task 12 contradicts Task 9 | Remove Task 12 (already implemented in Task 9) |
| **High** | 6 | Unlinked Task.start for initial rollup | Use supervised task with error handling |
| **High** | 9 | No max range limit for custom dates | Cap to 90 days |
| **Medium** | 8 | Commit includes wrong file (root.html.heex) | Remove from commit |
| **Medium** | 9 | Dead code: `time_ranges/0` never called | Remove function |
| **Medium** | 7 | Need TaskSupervisor for supervised tasks | Add to application.ex |
| **Critical** | 4 | upsert_bucket fetch-then-merge has TOCTOU race | Use raw SQL `ON CONFLICT UPDATE SET count = count + EXCLUDED.count` |
| **High** | 6 | `array_agg(row_to_json(e))` still used despite amendment | Implement streaming or document as tech debt with event limit |
| **High** | 9 | `String.to_atom(tab)` creates atoms before validation | Match on string directly, then convert |
| **Medium** | 9 | `phx-blur` on each input sends only one field | Use form with `phx-change` to send both values |
| **Medium** | 14 | `register_and_log_in_admin` helper not defined | Add note about existing helper or define it |
| **Low** | 9 | Custom range doesn't validate `from < to` | Add validation to reject invalid ranges |
| **Low** | 15 | Manual test emits to current minute but rollup processes previous | Fix test instructions timing |
| **High** | 6 | `Stream.chunk_by` creates unbounded chunks (100k events = OOM) | Use incremental aggregation with Stream.transform |
| **Medium** | 9 | `custom_range` nil check passes when value is nil | Check `is_binary` as well as non-empty |
| **Low** | 4 | `Repo.load` receives string keys from SQL columns | Convert to atoms for safety |

---

## Task 0: Remove LiveDashboard Dependency (Preserve Useful Components)

**Background:** The `phoenix_live_dashboard` dependency was previously added but we're replacing it with a custom metrics dashboard. This task removes LiveDashboard while preserving components that are useful for the new metrics dashboard.

**Components to REMOVE:**
- `phoenix_live_dashboard` dependency
- LiveDashboard route (`/admin/live-dashboard`)
- `import Phoenix.LiveDashboard.Router`
- `live_dashboard.css` file
- CSS import in `app.css`
- Sidebar link to "Live Dashboard"

**Components to PRESERVE (already useful for metrics dashboard):**
- `require_admin_plug` pipeline in router.ex (reusable for metrics route)
- `verify_admin_access/2` function in router.ex
- `admins_only/1` function in hooks.ex
- `BezgelorCore.TelemetryEvent` module (event declaration convention)
- `mix bezgelor.telemetry.discover` task
- All `@telemetry_events` declarations across apps
- Telemetry metrics configuration in `telemetry.ex`

**Files:**
- Modify: `apps/bezgelor_portal/mix.exs`
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/router.ex`
- Modify: `apps/bezgelor_portal/assets/css/app.css`
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/components/layouts.ex`
- Delete: `apps/bezgelor_portal/assets/css/live_dashboard.css`

**Step 1: Remove LiveDashboard dependency from mix.exs**

In `apps/bezgelor_portal/mix.exs`, remove:

```elixir
      # LiveDashboard
      {:phoenix_live_dashboard, "~> 0.8"}
```

**Step 2: Run mix deps.get**

Run: `mix deps.get`
Expected: Dependencies updated, phoenix_live_dashboard removed

**Step 3: Remove LiveDashboard import and route from router.ex**

In `apps/bezgelor_portal/lib/bezgelor_portal_web/router.ex`:

Remove line 3:
```elixir
  import Phoenix.LiveDashboard.Router
```

Remove the LiveDashboard scope (lines 148-158):
```elixir
  # LiveDashboard for admins (outside live_session, uses plug-based auth)
  scope "/admin" do
    pipe_through [:require_admin_plug]

    live_dashboard "/live-dashboard",
      metrics: BezgelorPortalWeb.Telemetry,
      ecto_repos: [BezgelorDb.Repo],
      ecto_psql_extras_options: [long_running_queries: [threshold: "200 milliseconds"]],
      env_keys: ["POSTGRES_HOST", "POSTGRES_PORT", "MIX_ENV"],
      additional_pages: []
  end
```

**NOTE:** Keep the `require_admin_plug` pipeline and `verify_admin_access/2` function - they will be reused for the metrics dashboard route.

**⚠️ AMENDMENT: Orphaned Pipeline**

The `require_admin_plug` pipeline becomes orphaned after this task because the new metrics route in Task 10 uses `live_session` (socket-based auth) rather than plug-based auth. Either:
1. Remove the orphaned pipeline in this task, OR
2. Keep it for future non-LiveView admin routes

Decision: Remove it unless there's a concrete future use case.

**Step 4: Remove CSS import from app.css**

In `apps/bezgelor_portal/assets/css/app.css`, remove the last two lines:

```css
/* LiveDashboard custom styling */
@import "./live_dashboard.css";
```

**Step 5: Delete live_dashboard.css**

Run: `rm apps/bezgelor_portal/assets/css/live_dashboard.css`

**Step 6: Remove sidebar link from layouts.ex**

In `apps/bezgelor_portal/lib/bezgelor_portal_web/components/layouts.ex`, around line 264, remove:

```elixir
            %{href: "/admin/live-dashboard", label: "Live Dashboard", permission: "server.view_logs", external: true},
```

**Step 7: Verify application compiles**

Run: `mix compile`
Expected: Compiles without errors

**Step 8: Verify no references remain**

Run: `grep -r "live_dashboard\|LiveDashboard" apps/bezgelor_portal/`
Expected: No matches (except possibly test files or comments)

**Step 9: Archive the superseded LiveDashboard plan**

Move the old plan to indicate it's superseded:

Run: `mv docs/plans/2025-12-21-livedashboard-telemetry-integration.md docs/plans/archive/2025-12-21-livedashboard-telemetry-integration.md`

If the archive directory doesn't exist:
Run: `mkdir -p docs/plans/archive && mv docs/plans/2025-12-21-livedashboard-telemetry-integration.md docs/plans/archive/`

**Step 10: Commit**

```bash
git add -A
git commit -m "refactor(portal): remove LiveDashboard dependency in favor of custom metrics dashboard

BREAKING: Removes /admin/live-dashboard route

Preserved components for reuse:
- require_admin_plug pipeline
- admins_only/1 auth function
- TelemetryEvent module
- telemetry.discover mix task
- All @telemetry_events declarations

Archived: docs/plans/2025-12-21-livedashboard-telemetry-integration.md"
```

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

    # ⚠️ AMENDMENT: SQL functions for atomic JSONB merging in upserts
    # These are required by the upsert_bucket function in Metrics context.

    # Merge two JSONB objects, adding numeric values for matching keys
    execute """
    CREATE OR REPLACE FUNCTION jsonb_merge_add(a jsonb, b jsonb) RETURNS jsonb AS $$
    SELECT COALESCE(
      jsonb_object_agg(
        key,
        COALESCE((a->>key)::numeric, 0) + COALESCE((b->>key)::numeric, 0)
      ),
      '{}'::jsonb
    )
    FROM (SELECT DISTINCT key FROM (
      SELECT key FROM jsonb_each_text(COALESCE(a, '{}'))
      UNION
      SELECT key FROM jsonb_each_text(COALESCE(b, '{}'))
    ) keys) k;
    $$ LANGUAGE SQL IMMUTABLE;
    """, "DROP FUNCTION IF EXISTS jsonb_merge_add(jsonb, jsonb);"

    # Merge two JSONB objects, taking minimum numeric value for matching keys
    execute """
    CREATE OR REPLACE FUNCTION jsonb_merge_min(a jsonb, b jsonb) RETURNS jsonb AS $$
    SELECT COALESCE(
      jsonb_object_agg(
        key,
        LEAST(
          COALESCE((a->>key)::numeric, 'infinity'::numeric),
          COALESCE((b->>key)::numeric, 'infinity'::numeric)
        )
      ),
      '{}'::jsonb
    )
    FROM (SELECT DISTINCT key FROM (
      SELECT key FROM jsonb_each_text(COALESCE(a, '{}'))
      UNION
      SELECT key FROM jsonb_each_text(COALESCE(b, '{}'))
    ) keys) k;
    $$ LANGUAGE SQL IMMUTABLE;
    """, "DROP FUNCTION IF EXISTS jsonb_merge_min(jsonb, jsonb);"

    # Merge two JSONB objects, taking maximum numeric value for matching keys
    execute """
    CREATE OR REPLACE FUNCTION jsonb_merge_max(a jsonb, b jsonb) RETURNS jsonb AS $$
    SELECT COALESCE(
      jsonb_object_agg(
        key,
        GREATEST(
          COALESCE((a->>key)::numeric, '-infinity'::numeric),
          COALESCE((b->>key)::numeric, '-infinity'::numeric)
        )
      ),
      '{}'::jsonb
    )
    FROM (SELECT DISTINCT key FROM (
      SELECT key FROM jsonb_each_text(COALESCE(a, '{}'))
      UNION
      SELECT key FROM jsonb_each_text(COALESCE(b, '{}'))
    ) keys) k;
    $$ LANGUAGE SQL IMMUTABLE;
    """, "DROP FUNCTION IF EXISTS jsonb_merge_max(jsonb, jsonb);"
  end
end
```

**⚠️ AMENDMENT: Use BRIN Indexes for Time-Series Data**

For time-series data like telemetry events, BRIN indexes are more efficient than B-tree indexes because:
- Data is naturally ordered by `occurred_at`/`bucket_start` (insert order matches physical order)
- BRIN indexes are ~100x smaller than B-tree for time columns
- Range scans are the primary access pattern

Replace the time-based B-tree indexes with BRIN:

```elixir
# Instead of:
create index(:telemetry_events, [:occurred_at])

# Use:
create index(:telemetry_events, [:occurred_at], using: :brin)

# Also for buckets:
create index(:telemetry_buckets, [:bucket_start], using: :brin)
```

Keep B-tree for `event_name` columns (high cardinality, exact match).

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

  ⚠️ CRITICAL: Uses raw SQL with ON CONFLICT for atomic upsert.
  This avoids TOCTOU race conditions that occur with fetch-then-merge.
  """
  @spec upsert_bucket(map()) :: {:ok, TelemetryBucket.t()} | {:error, term()}
  def upsert_bucket(attrs) do
    # Validate event_name to prevent atom exhaustion attacks
    unless is_binary(attrs.event_name) and String.match?(attrs.event_name, ~r/^[a-z0-9._]+$/) do
      raise ArgumentError, "Invalid event_name format: #{inspect(attrs.event_name)}"
    end

    # ⚠️ AMENDMENT: Use raw SQL with ON CONFLICT for atomic upsert
    # The previous fetch-then-merge pattern had a TOCTOU race condition:
    # - Between get_by and insert/update, another process could modify the row
    # - This caused constraint violations or lost updates
    #
    # Raw SQL with ON CONFLICT DO UPDATE is atomic and handles concurrency correctly.
    # The jsonb_each_text + aggregation pattern merges JSON values properly.
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

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
      attrs.count,
      attrs.sum_values || %{},
      attrs.min_values || %{},
      attrs.max_values || %{},
      attrs.metadata_counts || %{},
      now
    ]) do
      {:ok, %{rows: [row], columns: columns}} ->
        # ⚠️ AMENDMENT: Convert string column names to atoms for Repo.load
        # SQL columns are strings, but Ecto schemas expect atom keys
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

  # Note: The jsonb_merge_add, jsonb_merge_min, jsonb_merge_max functions must be
  # created in the database. Add to the migration:
  #
  # execute """
  # CREATE OR REPLACE FUNCTION jsonb_merge_add(a jsonb, b jsonb) RETURNS jsonb AS $$
  # SELECT COALESCE(
  #   jsonb_object_agg(
  #     key,
  #     COALESCE((a->>key)::numeric, 0) + COALESCE((b->>key)::numeric, 0)
  #   ),
  #   '{}'::jsonb
  # )
  # FROM (SELECT DISTINCT key FROM (
  #   SELECT key FROM jsonb_each_text(COALESCE(a, '{}'))
  #   UNION
  #   SELECT key FROM jsonb_each_text(COALESCE(b, '{}'))
  # ) keys) k;
  # $$ LANGUAGE SQL IMMUTABLE;
  # """
  #
  # Similar for jsonb_merge_min and jsonb_merge_max using LEAST/GREATEST.

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

  # ⚠️ AMENDMENT: Make tracked events configurable via application env
  # This allows adding/removing events without code changes.
  # In config.exs: config :bezgelor_portal, :telemetry_events, [[:bezgelor, :auth, :login_complete], ...]
  @default_tracked_events [
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

  defp tracked_events do
    Application.get_env(:bezgelor_portal, :telemetry_events, @default_tracked_events)
  end

  # ⚠️ AMENDMENT: Whitelist allowed metadata keys to prevent PII exposure
  # Raw metadata could contain sensitive values (emails, IPs, tokens, etc.)
  # ⚠️ AMENDMENT: Use atoms since telemetry metadata typically has atom keys
  @allowed_metadata_keys [:account_id, :character_id, :zone_id, :success, :creature_id,
                          :quest_id, :item_id, :spell_id, :guild_id, :world_id]

  defp sanitize_metadata(metadata) when is_map(metadata) do
    # ⚠️ AMENDMENT: Handle both atom and string keys from telemetry
    metadata
    |> Enum.filter(fn {k, _v} -> normalize_key(k) in @allowed_metadata_keys end)
    |> Enum.into(%{}, fn {k, v} -> {to_string(k), sanitize_value(v)} end)
  end
  defp sanitize_metadata(_), do: %{}

  # Normalize key to atom for comparison (handles both atom and string keys)
  defp normalize_key(k) when is_atom(k), do: k
  defp normalize_key(k) when is_binary(k) do
    try do
      String.to_existing_atom(k)
    rescue
      ArgumentError -> nil  # Unknown string key
    end
  end
  defp normalize_key(_), do: nil

  defp sanitize_value(v) when is_binary(v) and byte_size(v) > 100, do: String.slice(v, 0, 100)
  defp sanitize_value(v), do: v

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    flush_interval = Keyword.get(opts, :flush_interval, @default_flush_interval)
    max_buffer_size = Keyword.get(opts, :max_buffer_size, @default_max_buffer_size)

    # Attach to telemetry events - returns list of handler IDs
    handler_ids = attach_handlers()

    # Schedule periodic flush (unless :infinity for testing)
    if flush_interval != :infinity do
      schedule_flush(flush_interval)
    end

    {:ok,
     %{
       buffer: [],
       flush_interval: flush_interval,
       max_buffer_size: max_buffer_size,
       handler_ids: handler_ids  # ⚠️ Store for cleanup in terminate
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
      metadata: sanitize_metadata(metadata),  # ⚠️ AMENDMENT: Sanitize to prevent PII
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

  # ⚠️ AMENDMENT: Store handler IDs in state to detach on terminate
  defp attach_handlers do
    tracked_events()
    |> Enum.map(fn event ->
      handler_id = "telemetry_collector_#{Enum.join(event, "_")}_#{:erlang.pid_to_list(self())}"

      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_event/4,
        %{collector: self()}
      )

      handler_id
    end)
  end

  # ⚠️ CRITICAL: Detach handlers on terminate to prevent leaks
  # If the GenServer restarts, old handlers with stale PIDs remain attached
  # and will fail silently, losing telemetry data.
  @impl true
  def terminate(_reason, state) do
    Enum.each(state.handler_ids || [], fn handler_id ->
      :telemetry.detach(handler_id)
    end)
    :ok
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
      # ⚠️ AMENDMENT: Events must be in the PREVIOUS complete minute.
      # rollup_minute() processes the last COMPLETE minute, not the current one.
      # If now is 14:32:45, rollup processes 14:31:00-14:32:00.
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      current_minute_start = now |> Map.put(:second, 0)
      # The bucket rollup_minute() will process:
      previous_minute_start = DateTime.add(current_minute_start, -60, :second)
      # Insert events in the MIDDLE of the previous minute (30 seconds in)
      event_time = DateTime.add(previous_minute_start, 30, :second)

      # Insert test events in the PREVIOUS minute
      Metrics.insert_events([
        %{
          event_name: "test.event",
          measurements: %{"value" => 10},
          metadata: %{"tag" => "a"},
          occurred_at: event_time
        },
        %{
          event_name: "test.event",
          measurements: %{"value" => 20},
          metadata: %{"tag" => "a"},
          occurred_at: event_time
        }
      ])

      # Run rollup (processes previous minute)
      RollupScheduler.rollup_minute()

      # Check bucket was created for the PREVIOUS minute
      buckets = Metrics.query_buckets("test.event", :minute, previous_minute_start, current_minute_start)
      assert length(buckets) == 1

      bucket = hd(buckets)
      assert bucket.count == 2
      assert bucket.sum_values["value"] == 30
      assert bucket.bucket_start == previous_minute_start
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
    # ⚠️ AMENDMENT: Run initial rollup on startup to catch events
    # that accumulated while the scheduler was down.
    # Run async to not block supervisor startup.
    # ⚠️ AMENDMENT: Use Task.Supervisor for proper error handling.
    # Unlinked Task.start means errors are silently swallowed.
    Task.Supervisor.start_child(BezgelorPortal.TaskSupervisor, fn ->
      Process.sleep(5_000)  # Wait for other services
      rollup_minute()
      rollup_hour()
    end)

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

  ⚠️ AMENDMENT: Uses LAST COMPLETE minute, not current partial minute.
  This ensures idempotent rollups even if scheduler drifts or restarts.
  """
  def rollup_minute do
    now = DateTime.utc_now()
    # Truncate to current minute boundary, then go back one minute
    # This gives us the LAST COMPLETE minute
    current_minute = now |> DateTime.truncate(:second) |> Map.put(:second, 0)
    bucket_end = current_minute
    bucket_start = DateTime.add(bucket_end, -60, :second)

    aggregate_events_to_buckets(bucket_start, bucket_end, :minute)
  end

  @doc """
  Aggregate minute buckets from the last hour into hour buckets.

  ⚠️ AMENDMENT: Uses LAST COMPLETE hour.
  """
  def rollup_hour do
    now = DateTime.utc_now()
    # Truncate to current hour boundary, then go back one hour
    current_hour = now |> DateTime.truncate(:second) |> Map.put(:second, 0) |> Map.put(:minute, 0)
    bucket_end = current_hour
    bucket_start = DateTime.add(bucket_end, -3600, :second)

    aggregate_buckets(:minute, bucket_start, bucket_end, :hour, bucket_start)
  end

  @doc """
  Aggregate hour buckets from the last day into day buckets.

  ⚠️ AMENDMENT: Uses YESTERDAY, not today (which is incomplete).
  """
  def rollup_day do
    now = DateTime.utc_now()
    today = DateTime.to_date(now)
    today_start = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
    # Yesterday's complete day
    bucket_start = DateTime.add(today_start, -86400, :second)
    bucket_end = today_start

    aggregate_buckets(:hour, bucket_start, bucket_end, :day, bucket_start)
  end

  defp aggregate_events_to_buckets(from, to, bucket_type) do
    # ⚠️ AMENDMENT: Use incremental aggregation to avoid loading all events into memory
    # The original array_agg(row_to_json(e)) loads ALL events into memory.
    # Stream.chunk_by also creates unbounded chunks (100k events with same name = OOM).
    #
    # This implementation uses Stream.transform for true incremental aggregation:
    # - Each event is processed one at a time
    # - Aggregates are accumulated in a map keyed by event_name
    # - Only the aggregates are kept in memory, not the events

    bucket_start_truncated =
      from |> DateTime.truncate(:second) |> Map.put(:second, 0)

    # Use a transaction for streaming (required by Ecto)
    {:ok, aggregates} = Repo.transaction(fn ->
      TelemetryEvent
      |> where([e], e.occurred_at >= ^from and e.occurred_at < ^to)
      |> Repo.stream(max_rows: 500)
      |> Enum.reduce(%{}, fn event, acc ->
        # ⚠️ AMENDMENT: Incremental aggregation - never holds more than one event at a time
        event_name = event.event_name
        measurements = event.measurements || %{}
        metadata = event.metadata || %{}

        # Get or initialize aggregate for this event_name
        current = Map.get(acc, event_name, %{
          count: 0,
          sum_values: %{},
          min_values: %{},
          max_values: %{},
          metadata_counts: %{}
        })

        # Merge this event into the aggregate
        updated = %{
          count: current.count + 1,
          sum_values: Map.merge(current.sum_values, measurements, fn _k, v1, v2 ->
            (v1 || 0) + (v2 || 0)
          end),
          min_values: Map.merge(current.min_values, measurements, fn _k, v1, v2 ->
            min(v1, v2)
          end),
          max_values: Map.merge(current.max_values, measurements, fn _k, v1, v2 ->
            max(v1, v2)
          end),
          metadata_counts: (
            meta_key = metadata |> Enum.sort() |> Enum.map(fn {k, v} -> "#{k}:#{v}" end) |> Enum.join(",")
            Map.update(current.metadata_counts, meta_key, 1, &(&1 + 1))
          )
        }

        Map.put(acc, event_name, updated)
      end)
    end, timeout: :infinity)

    # Now upsert all the aggregated buckets
    Enum.each(aggregates, fn {event_name, agg} ->
      Metrics.upsert_bucket(%{
        event_name: event_name,
        bucket_type: bucket_type,
        bucket_start: bucket_start_truncated,
        count: agg.count,
        sum_values: agg.sum_values,
        min_values: agg.min_values,
        max_values: agg.max_values,
        metadata_counts: agg.metadata_counts
      })
    end)

    Logger.debug("RollupScheduler: aggregated #{bucket_type} buckets from #{from} to #{to}")
  end

  defp aggregate_buckets(source_type, from, to, target_type, target_start) do
    # ⚠️ AMENDMENT: Removed dead code - the `query` variable below was never used
    # The actual implementation uses Enum.group_by instead.

    # Fetch and aggregate source buckets
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
      # ⚠️ AMENDMENT: Task supervisor for async tasks (must start before RollupScheduler)
      {Task.Supervisor, name: BezgelorPortal.TaskSupervisor},
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

**Step 3: Bundle Chart.js via esbuild (NOT CDN)**

**⚠️ AMENDMENT: Bundle Chart.js instead of CDN**

External CDN scripts violate bundling best practices and add CSP complexity. Bundle via npm/esbuild instead.

**Step 3a: Install Chart.js npm packages**

Run:
```bash
cd apps/bezgelor_portal/assets
npm install chart.js chartjs-adapter-date-fns
```

**Step 3b: Import in app.js**

Edit `apps/bezgelor_portal/assets/js/app.js`, add near the top:

```javascript
// Chart.js - bundled for reliability and CSP compliance
import Chart from "chart.js/auto"
import "chartjs-adapter-date-fns"

// Make Chart available globally for the hook
window.Chart = Chart
```

**Step 3c: Update the hook to not assume global Chart**

The hook should already work since we set `window.Chart`, but for cleaner code, update `metrics_chart.js`:

```javascript
// If using ES modules directly:
// import Chart from "chart.js/auto"

const MetricsChart = {
  mounted() {
    // Chart is available via window.Chart from app.js import
    if (typeof Chart === "undefined") {
      console.error("Chart.js not loaded")
      return
    }
    // ... rest of hook
  }
  // ...
}
```

**No layout changes needed** - Chart.js is now bundled in app.js.

**Step 4: Commit**

```bash
# ⚠️ AMENDMENT: No root.html.heex changes - Chart.js is bundled via npm/esbuild
git add apps/bezgelor_portal/assets/js/metrics_chart.js apps/bezgelor_portal/assets/js/app.js apps/bezgelor_portal/assets/package.json apps/bezgelor_portal/assets/package-lock.json
git commit -m "feat(portal): add Chart.js hook for metrics visualization

Bundles Chart.js via npm/esbuild for CSP compliance and reliability."
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

  # ⚠️ AMENDMENT: Use keyword list to preserve order in UI
  # Maps in Elixir don't preserve insertion order, so buttons would appear random.
  @time_ranges [
    {"1h", 1},
    {"6h", 6},
    {"24h", 24},
    {"7d", 24 * 7},
    {"30d", 24 * 30}
  ]

  # ⚠️ AMENDMENT: @valid_tabs removed - replaced by @tab_mapping in handle_event
  # The mapping approach is safer because String.to_atom is never called on user input.

  @impl true
  def mount(_params, _session, socket) do
    # ⚠️ AMENDMENT: Use Process.send_after instead of :timer.send_interval
    # :timer.send_interval creates a timer process that isn't linked to the LiveView,
    # causing memory leaks when the LiveView terminates (timer keeps running).
    # Process.send_after self-cleans when the process dies.
    if connected?(socket) do
      schedule_refresh()
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

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  @impl true
  def handle_info(:refresh, socket) do
    # ⚠️ AMENDMENT: Reschedule next refresh
    schedule_refresh()
    {:noreply, load_chart_data(socket)}
  end

  # ⚠️ AMENDMENT: Map strings to atoms to prevent atom exhaustion attacks
  # String.to_atom/1 creates atoms for ANY input, even before validation.
  # This approach only allows the 4 known tab values.
  @tab_mapping %{
    "server" => :server,
    "auth" => :auth,
    "gameplay" => :gameplay,
    "combat" => :combat
  }

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    # ⚠️ AMENDMENT: Match on string first, then get atom from safe mapping
    case Map.get(@tab_mapping, tab) do
      nil ->
        {:noreply, socket}

      tab_atom ->
        {:noreply,
         socket
         |> assign(active_tab: tab_atom)
         |> load_chart_data()}
    end
  end

  @impl true
  def handle_event("change_time_range", %{"range" => range}, socket) do
    {:noreply,
     socket
     |> assign(time_range: range, custom_from: nil, custom_to: nil)
     |> load_chart_data()}
  end

  @impl true
  def handle_event("custom_range", params, socket) do
    # ⚠️ AMENDMENT: Handle form phx-change which sends all form fields
    # Also handle case where one field is empty during typing
    from = Map.get(params, "from", socket.assigns.custom_from)
    to = Map.get(params, "to", socket.assigns.custom_to)

    # ⚠️ AMENDMENT: Check is_binary to handle nil values correctly
    # nil != "" is true, so we must explicitly check for binary strings
    if is_binary(from) and from != "" and is_binary(to) and to != "" do
      {:noreply,
       socket
       |> assign(time_range: "custom", custom_from: from, custom_to: to)
       |> load_chart_data()}
    else
      # Store partial values but don't reload data yet
      {:noreply, assign(socket, custom_from: from, custom_to: to)}
    end
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

      <%!-- ⚠️ AMENDMENT: Use list syntax for classes (modern HEEx style) --%>
      <!-- Time Range Selector -->
      <div class="flex items-center gap-4">
        <div class="flex gap-1">
          <button
            :for={{label, _} <- @time_ranges}
            type="button"
            class={[
              "px-3 py-1 text-sm rounded font-medium transition-colors",
              @time_range == label && "bg-primary text-primary-content",
              @time_range != label && "bg-base-200 hover:bg-base-300"
            ]}
            phx-click="change_time_range"
            phx-value-range={label}
          >
            {label}
          </button>
        </div>
        <%!-- ⚠️ AMENDMENT: Wrap in form with phx-change to send both values --%>
        <%!-- phx-blur on individual inputs only sends that field's value --%>
        <form phx-change="custom_range" class="flex items-center gap-2">
          <input
            type="datetime-local"
            name="from"
            class="input input-sm input-bordered"
            value={@custom_from}
            phx-debounce="500"
          />
          <span>to</span>
          <input
            type="datetime-local"
            name="to"
            class="input input-sm input-bordered"
            value={@custom_to}
            phx-debounce="500"
          />
        </form>
      </div>

      <!-- Tabs -->
      <div role="tablist" class="flex gap-1 bg-base-200 p-1 rounded-lg w-fit">
        <button
          :for={tab <- [:server, :auth, :gameplay, :combat]}
          type="button"
          role="tab"
          class={[
            "px-4 py-2 text-sm font-medium rounded transition-colors",
            @active_tab == tab && "bg-base-100 shadow",
            @active_tab != tab && "hover:bg-base-300"
          ]}
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

    # ⚠️ AMENDMENT: Only load data for the active tab to reduce DB queries
    # Previously loaded all 4 tabs on every refresh, causing unnecessary load.
    socket =
      case socket.assigns.active_tab do
        :server -> load_server_data(socket, from, to, bucket_type, time_unit)
        :auth -> load_auth_data(socket, from, to, bucket_type, time_unit)
        :gameplay -> load_gameplay_data(socket, from, to, bucket_type, time_unit)
        :combat -> load_combat_data(socket, from, to, bucket_type, time_unit)
      end

    push_chart_updates(socket)
  end

  defp get_time_range(assigns) do
    now = DateTime.utc_now()

    {from, to} =
      case assigns.time_range do
        "custom" ->
          parse_custom_range(assigns.custom_from, assigns.custom_to, now)

        range ->
          # ⚠️ AMENDMENT: Use List.keyfind for keyword list lookup
          hours = case List.keyfind(@time_ranges, range, 0) do
            {_, h} -> h
            nil -> 1
          end
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

  # ⚠️ AMENDMENT: Max 90 days for custom date range to prevent excessive queries
  @max_custom_range_days 90

  defp parse_custom_range(nil, _, now), do: {DateTime.add(now, -1, :hour), now}
  defp parse_custom_range(_, nil, now), do: {DateTime.add(now, -1, :hour), now}

  defp parse_custom_range(from_str, to_str, now) do
    with {:ok, from} <- NaiveDateTime.from_iso8601(from_str),
         {:ok, to} <- NaiveDateTime.from_iso8601(to_str) do
      from_dt = DateTime.from_naive!(from, "Etc/UTC")
      to_dt = DateTime.from_naive!(to, "Etc/UTC")

      # ⚠️ AMENDMENT: Validate from < to (reject invalid ranges)
      # Also enforce max range limit
      days_diff = DateTime.diff(to_dt, from_dt, :day)

      cond do
        # Invalid: from >= to (negative or zero range)
        days_diff < 0 ->
          # Swap them if user entered backwards
          parse_custom_range(to_str, from_str, now)

        days_diff == 0 and DateTime.compare(from_dt, to_dt) != :lt ->
          # Same day but from >= to in time
          {DateTime.add(now, -1, :hour), now}

        # Exceeds max range
        days_diff > @max_custom_range_days ->
          # Cap the from date to 90 days before to
          {DateTime.add(to_dt, -@max_custom_range_days, :day), to_dt}

        true ->
          {from_dt, to_dt}
      end
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
    # ⚠️ AMENDMENT: Only push when connected to avoid unnecessary event queueing
    unless connected?(socket) do
      socket
    else
      # ⚠️ AMENDMENT: Only push updates for active tab's charts
      # Avoids trying to access assigns that don't exist for inactive tabs.
      case socket.assigns.active_tab do
      :server ->
        socket
        |> push_event("update_chart_players-chart", socket.assigns.players_data)
        |> push_event("update_chart_creatures-chart", socket.assigns.creatures_data)
        |> push_event("update_chart_zones-chart", socket.assigns.zones_data)

      :auth ->
        socket
        |> push_event("update_chart_logins-chart", socket.assigns.logins_data)
        |> push_event("update_chart_sessions-chart", socket.assigns.sessions_data)
        |> push_event("update_chart_login-success-chart", socket.assigns.login_success_data)

      :gameplay ->
        socket
        |> push_event("update_chart_world-entry-chart", socket.assigns.world_entry_data)
        |> push_event("update_chart_quests-accepted-chart", socket.assigns.quests_accepted_data)
        |> push_event("update_chart_quests-completed-chart", socket.assigns.quests_completed_data)

      :combat ->
        socket
        |> push_event("update_chart_kills-chart", socket.assigns.kills_data)
        |> push_event("update_chart_xp-chart", socket.assigns.xp_data)
        |> push_event("update_chart_damage-chart", socket.assigns.damage_data)
      end
    end
  end

  # ⚠️ AMENDMENT: Removed dead code `defp time_ranges, do: @time_ranges`
  # It was never called - @time_ranges is used directly where needed.
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

Look for the Server sidebar section with admin links (around line 260-270).

**Step 2: Add Metrics Dashboard link**

Add where the "Live Dashboard" link was removed in Task 0, after "Server Status":

```elixir
            %{href: "/admin/metrics", label: "Metrics", permission: "server.view_logs"},
```

The Server section should now look like:
```elixir
        <.sidebar_section
          title="Server"
          icon="hero-server"
          permission_set={@permission_set}
          links={[
            %{href: "/admin/server", label: "Server Status", permission: "server.view_logs"},
            %{href: "/admin/metrics", label: "Metrics", permission: "server.view_logs"},
            %{href: "/admin/server/logs", label: "Logs", permission: "server.view_logs"},
            %{href: "/admin/settings", label: "Server Settings", permission: "server.settings"}
          ]}
        />
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

**⚠️ AMENDMENT: THIS TASK IS SUPERSEDED BY TASK 9**

Task 9 already includes the corrected `push_chart_updates/1` implementation that:
1. Only pushes events for the active tab's charts (not all 12 charts)
2. Gates with `connected?(socket)` check
3. Uses the correct per-chart event targeting pattern

The `push_chart_updates/1` shown below is **OUT OF DATE** - it pushes ALL charts regardless of active tab.

**SKIP THIS TASK** - The correct implementation is already in Task 9.

---

**Files (OUTDATED - see Task 9):**
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

**⚠️ AMENDMENT: Always render canvas so hooks can attach**

The original implementation conditionally renders the canvas, which prevents the `phx-hook` from attaching when there's no data. Then when data arrives, the hook doesn't exist to receive `update_chart` events.

**Fixed implementation:** Always render the canvas, but show an overlay message when empty:

```elixir
defp chart_card(assigns) do
  has_data = length(assigns.chart_data[:labels] || []) > 0
  assigns = assign(assigns, :has_data, has_data)

  ~H"""
  <div class="card bg-base-100 shadow">
    <div class="card-body">
      <h3 class="card-title text-base">{@title}</h3>
      <div class="h-64 relative">
        <%!-- ⚠️ Always render canvas so hook can attach --%>
        <canvas
          id={@id}
          phx-hook="MetricsChart"
          phx-update="ignore"
          data-chart-type={@chart_type}
          data-chart-title={@title}
        >
        </canvas>
        <%!-- Overlay message when no data --%>
        <%= unless @has_data do %>
          <div class="absolute inset-0 flex items-center justify-center bg-base-100/80">
            <div class="text-center text-base-content/50">
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

**⚠️ AMENDMENT: Add missing tests before running suite**

The following tests are missing and should be added:

**1. Metrics purge test** (`apps/bezgelor_db/test/metrics_test.exs`):

```elixir
describe "purge_events_before/1" do
  test "deletes events older than cutoff" do
    old = DateTime.add(DateTime.utc_now(), -72, :hour)
    new = DateTime.utc_now()

    Metrics.insert_events([
      %{event_name: "test.event", measurements: %{}, metadata: %{}, occurred_at: old},
      %{event_name: "test.event", measurements: %{}, metadata: %{}, occurred_at: new}
    ])

    cutoff = DateTime.add(DateTime.utc_now(), -48, :hour)
    {count, _} = Metrics.purge_events_before(cutoff)

    assert count == 1
    assert length(Metrics.query_events("test.event", DateTime.add(new, -1, :hour), new)) == 1
  end
end
```

**2. LiveView test** (`apps/bezgelor_portal/test/live/admin/metrics_dashboard_live_test.exs`):

**⚠️ AMENDMENT: Test helper requirement**

The `register_and_log_in_admin` helper should already exist in `apps/bezgelor_portal/test/support/conn_case.ex`.
If not, add it:

```elixir
# In ConnCase module
def register_and_log_in_admin(%{conn: conn}) do
  admin = BezgelorDb.AccountsFixtures.admin_fixture()
  %{conn: log_in_account(conn, admin), admin: admin}
end
```

```elixir
defmodule BezgelorPortalWeb.Admin.MetricsDashboardLiveTest do
  use BezgelorPortalWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  @moduletag :database

  setup :register_and_log_in_admin

  test "renders dashboard with tabs", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/metrics")

    assert html =~ "Metrics Dashboard"
    assert html =~ "Server"
    assert html =~ "Auth"
    assert html =~ "Gameplay"
    assert html =~ "Combat"
  end

  test "switches tabs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/metrics")

    html = view |> element("button", "Auth") |> render_click()
    assert html =~ "Login Rate"
  end

  test "changes time range", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/metrics")

    html = view |> element("button", "24h") |> render_click()
    # Verify time range changed (check for visual indicator or data reload)
    assert html =~ "24h"
  end
end
```

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

**⚠️ AMENDMENT: Timing note**

Events are emitted at the current time, but `rollup_minute()` processes the PREVIOUS complete minute.
Charts won't show data until a minute passes and the scheduler runs, OR you trigger rollup manually.

In IEx:

```elixir
# Emit some test events
:telemetry.execute([:bezgelor, :auth, :login_complete], %{duration_ms: 150}, %{account_id: 1, success: true})
:telemetry.execute([:bezgelor, :auth, :login_complete], %{duration_ms: 200}, %{account_id: 2, success: false})
:telemetry.execute([:bezgelor, :creature, :killed], %{xp_reward: 500}, %{creature_id: 1, zone_id: 100})

# Wait for flush (5 seconds)
Process.sleep(6000)

# Verify events stored in raw table
BezgelorDb.Metrics.query_events("bezgelor.auth.login_complete", DateTime.add(DateTime.utc_now(), -60, :second), DateTime.utc_now())

# ⚠️ AMENDMENT: To see data in charts immediately, either:
# Option A: Wait ~60 seconds for the scheduler to run rollup_minute()
# Option B: Manually trigger rollup (processes PREVIOUS minute):
#   BezgelorPortal.RollupScheduler.rollup_minute()
#
# Note: If you just emitted events, they're in the CURRENT minute.
# Wait until the clock rolls over to the next minute, then run rollup_minute().
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