defmodule BezgelorDb.Schema.EconomyAlert do
  @moduledoc """
  Database schema for economy alert tracking.

  Records suspicious or notable economic activity for monitoring and investigation.

  ## Fields

  - `alert_type` - Type of alert (high_value_trade, rapid_transactions, unusual_pattern, threshold_breach, currency_anomaly)
  - `severity` - Alert severity level (info, warning, critical)
  - `character_id` - Optional reference to the character involved
  - `description` - Human-readable description of the alert
  - `data` - JSON map with alert-specific details (transaction IDs, values, timestamps, etc.)
  - `acknowledged` - Whether the alert has been reviewed
  - `acknowledged_by` - Username of admin who acknowledged the alert
  - `acknowledged_at` - When the alert was acknowledged
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BezgelorDb.Schema.Character

  @type t :: %__MODULE__{
          id: integer() | nil,
          alert_type: String.t(),
          severity: String.t(),
          character_id: integer() | nil,
          character: Character.t() | Ecto.Association.NotLoaded.t() | nil,
          description: String.t(),
          data: map() | nil,
          acknowledged: boolean(),
          acknowledged_by: String.t() | nil,
          acknowledged_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @alert_types ~w(high_value_trade rapid_transactions unusual_pattern threshold_breach currency_anomaly)
  @severities ~w(info warning critical)

  schema "economy_alerts" do
    belongs_to(:character, Character)

    field(:alert_type, :string)
    field(:severity, :string)
    field(:description, :string)
    field(:data, :map)
    field(:acknowledged, :boolean, default: false)
    field(:acknowledged_by, :string)
    field(:acknowledged_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @required_fields [:alert_type, :severity, :description]
  @optional_fields [:character_id, :data, :acknowledged, :acknowledged_by, :acknowledged_at]

  @doc """
  Creates a changeset for an economy alert.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(alert, attrs) do
    alert
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:alert_type, @alert_types)
    |> validate_inclusion(:severity, @severities)
    |> foreign_key_constraint(:character_id)
  end

  @doc """
  Creates a changeset for acknowledging an alert.
  """
  @spec acknowledge_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def acknowledge_changeset(alert, admin_username) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    alert
    |> change(acknowledged: true, acknowledged_by: admin_username, acknowledged_at: now)
  end

  @doc """
  Checks if the alert is acknowledged.
  """
  @spec acknowledged?(t()) :: boolean()
  def acknowledged?(%__MODULE__{acknowledged: acknowledged}), do: acknowledged

  @doc """
  Checks if the alert is critical severity.
  """
  @spec critical?(t()) :: boolean()
  def critical?(%__MODULE__{severity: severity}), do: severity == "critical"

  @doc """
  Checks if the alert is warning severity.
  """
  @spec warning?(t()) :: boolean()
  def warning?(%__MODULE__{severity: severity}), do: severity == "warning"

  @doc """
  Checks if the alert is info severity.
  """
  @spec info?(t()) :: boolean()
  def info?(%__MODULE__{severity: severity}), do: severity == "info"

  @doc """
  Returns the list of valid alert types.
  """
  @spec alert_types() :: [String.t()]
  def alert_types, do: @alert_types

  @doc """
  Returns the list of valid severities.
  """
  @spec severities() :: [String.t()]
  def severities, do: @severities
end
