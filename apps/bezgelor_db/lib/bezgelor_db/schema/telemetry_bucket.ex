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
