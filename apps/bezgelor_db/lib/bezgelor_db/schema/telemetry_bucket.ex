defmodule BezgelorDb.Schema.TelemetryBucket do
  @moduledoc """
  Database schema for storing aggregated telemetry metrics.

  ## Overview

  TelemetryBucket stores pre-aggregated/rolled-up metrics for efficient
  dashboard queries. Metrics are aggregated into time buckets (minute, hour, day)
  to avoid scanning raw events for every dashboard request.

  ## Fields

  - `metric_name` - The metric identifier (e.g., "character.login", "combat.damage_dealt")
  - `bucket_start` - Start of the time bucket (UTC)
  - `bucket_end` - End of the time bucket (UTC)
  - `granularity` - Time bucket size: "minute", "hour", or "day"
  - `count` - Number of events aggregated in this bucket
  - `sum` - Sum of all values in the bucket
  - `min` - Minimum value in the bucket
  - `max` - Maximum value in the bucket
  - `avg` - Average value in the bucket (calculated: sum / count)
  - `dimensions` - Map of grouping dimensions (e.g., %{character_id: 123, zone_id: 456})

  ## Dimensions

  The dimensions field stores flexible grouping keys for drill-down analysis:

  - `character_id` - Character that triggered the event
  - `zone_id` - Zone where the event occurred
  - `faction_id` - Faction affiliation
  - `level` - Character level at time of event
  - Any other custom dimensions needed for analysis

  ## Example

      # Creating a bucket for combat damage in zone 51 for 1-hour period
      %TelemetryBucket{}
      |> TelemetryBucket.changeset(%{
        metric_name: "combat.damage_dealt",
        bucket_start: ~U[2025-12-21 10:00:00Z],
        bucket_end: ~U[2025-12-21 11:00:00Z],
        granularity: "hour",
        count: 1543,
        sum: 487234.5,
        min: 12.0,
        max: 9834.2,
        avg: 315.8,
        dimensions: %{zone_id: 51, faction_id: 1}
      })
      |> Repo.insert()
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          metric_name: String.t() | nil,
          bucket_start: DateTime.t() | nil,
          bucket_end: DateTime.t() | nil,
          granularity: String.t() | nil,
          count: integer() | nil,
          sum: float() | nil,
          min: float() | nil,
          max: float() | nil,
          avg: float() | nil,
          dimensions: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @granularity_types ~w(minute hour day)

  schema "telemetry_buckets" do
    field(:metric_name, :string)
    field(:bucket_start, :utc_datetime)
    field(:bucket_end, :utc_datetime)
    field(:granularity, :string)
    field(:count, :integer)
    field(:sum, :float)
    field(:min, :float)
    field(:max, :float)
    field(:avg, :float)
    field(:dimensions, :map)

    timestamps(type: :utc_datetime)
  end

  @required_fields [:metric_name, :bucket_start, :bucket_end, :granularity, :count]
  @optional_fields [:sum, :min, :max, :avg, :dimensions]

  @doc """
  Creates a changeset for a telemetry bucket.

  ## Validations

  - Required: metric_name, bucket_start, bucket_end, granularity, count
  - Granularity must be one of: minute, hour, day
  - Count must be positive
  - bucket_end must be after bucket_start
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(bucket, attrs) do
    bucket
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:granularity, @granularity_types)
    |> validate_number(:count, greater_than: 0)
    |> validate_bucket_times()
  end

  defp validate_bucket_times(changeset) do
    bucket_start = get_field(changeset, :bucket_start)
    bucket_end = get_field(changeset, :bucket_end)

    if bucket_start && bucket_end && DateTime.compare(bucket_end, bucket_start) != :gt do
      add_error(changeset, :bucket_end, "must be after bucket_start")
    else
      changeset
    end
  end

  @doc """
  Returns the list of valid granularity types.
  """
  @spec granularity_types() :: [String.t()]
  def granularity_types, do: @granularity_types

  @doc """
  Checks if this bucket is for minute-level granularity.
  """
  @spec minute_bucket?(t()) :: boolean()
  def minute_bucket?(%__MODULE__{granularity: granularity}), do: granularity == "minute"

  @doc """
  Checks if this bucket is for hour-level granularity.
  """
  @spec hour_bucket?(t()) :: boolean()
  def hour_bucket?(%__MODULE__{granularity: granularity}), do: granularity == "hour"

  @doc """
  Checks if this bucket is for day-level granularity.
  """
  @spec day_bucket?(t()) :: boolean()
  def day_bucket?(%__MODULE__{granularity: granularity}), do: granularity == "day"

  @doc """
  Gets a dimension value from the dimensions map.
  """
  @spec get_dimension(t(), atom() | String.t()) :: any()
  def get_dimension(%__MODULE__{dimensions: nil}, _key), do: nil

  def get_dimension(%__MODULE__{dimensions: dimensions}, key) when is_atom(key) do
    Map.get(dimensions, key) || Map.get(dimensions, to_string(key))
  end

  def get_dimension(%__MODULE__{dimensions: dimensions}, key) when is_binary(key) do
    Map.get(dimensions, key) || Map.get(dimensions, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(dimensions, key)
  end

  @doc """
  Checks if the bucket has a specific dimension.
  """
  @spec has_dimension?(t(), atom() | String.t()) :: boolean()
  def has_dimension?(%__MODULE__{dimensions: nil}, _key), do: false

  def has_dimension?(%__MODULE__{dimensions: dimensions}, key) when is_atom(key) do
    Map.has_key?(dimensions, key) || Map.has_key?(dimensions, to_string(key))
  end

  def has_dimension?(%__MODULE__{dimensions: dimensions}, key) when is_binary(key) do
    Map.has_key?(dimensions, key) || Map.has_key?(dimensions, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.has_key?(dimensions, key)
  end
end
