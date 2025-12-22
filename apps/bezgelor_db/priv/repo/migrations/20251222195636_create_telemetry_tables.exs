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

    # B-tree for event_name (exact match queries)
    create index(:telemetry_events, [:event_name])
    # BRIN for time column (range scans, naturally ordered by insert time)
    create index(:telemetry_events, [:occurred_at], using: :brin)
    # Composite index for filtered time queries
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
    # BRIN for time column
    create index(:telemetry_buckets, [:bucket_start], using: :brin)
    # Composite for filtered queries
    create index(:telemetry_buckets, [:event_name, :bucket_type])

    # SQL functions for atomic JSONB merging in upserts
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
