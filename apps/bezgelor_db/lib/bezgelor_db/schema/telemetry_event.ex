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
      metadata: metadata,
      occurred_at: DateTime.utc_now()
    })
  end
end
