defmodule BezgelorDb.Schema.TelemetryEvent do
  @moduledoc """
  Database schema for storing raw telemetry events.

  Captures telemetry events emitted throughout the application for metrics,
  monitoring, and analytics purposes. Events are stored with their full
  measurements and metadata for later aggregation and analysis.

  ## Fields

  - `event_name` - The telemetry event path (e.g., "bezgelor.economy.currency.transaction")
  - `measurements` - Map of numeric measurements from the telemetry event
  - `metadata` - Map of additional context and tags from the telemetry event
  - `inserted_at` - When the event was recorded
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          event_name: String.t() | nil,
          measurements: map() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "telemetry_events" do
    field(:event_name, :string)
    field(:measurements, :map)
    field(:metadata, :map)

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @required_fields [:event_name]
  @optional_fields [:measurements, :metadata]

  @doc """
  Creates a changeset for a telemetry event.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:event_name, min: 1, max: 255)
  end

  @doc """
  Creates a record from telemetry event data.
  """
  @spec from_telemetry(String.t() | [atom()], map(), map()) :: Ecto.Changeset.t()
  def from_telemetry(event_name, measurements, metadata) when is_list(event_name) do
    event_name_str = Enum.join(event_name, ".")
    from_telemetry(event_name_str, measurements, metadata)
  end

  def from_telemetry(event_name, measurements, metadata) when is_binary(event_name) do
    changeset(%__MODULE__{}, %{
      event_name: event_name,
      measurements: measurements,
      metadata: metadata
    })
  end
end
