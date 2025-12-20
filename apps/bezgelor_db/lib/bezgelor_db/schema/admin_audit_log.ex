defmodule BezgelorDb.Schema.AdminAuditLog do
  @moduledoc """
  Database schema for admin action audit logging.

  Records all administrative actions for accountability and debugging.

  ## Fields

  - `admin_account_id` - The admin who performed the action
  - `action` - The action performed (e.g., "user.ban", "character.grant_item")
  - `target_type` - Type of target (e.g., "account", "character")
  - `target_id` - ID of the target entity
  - `details` - JSON map with action-specific details
  - `ip_address` - IP address of the admin
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          admin_account_id: integer() | nil,
          action: String.t() | nil,
          target_type: String.t() | nil,
          target_id: integer() | nil,
          details: map() | nil,
          ip_address: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "admin_audit_log" do
    belongs_to(:admin_account, BezgelorDb.Schema.Account)

    field(:action, :string)
    field(:target_type, :string)
    field(:target_id, :integer)
    field(:details, :map)
    field(:ip_address, :string)

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc """
  Changeset for creating an audit log entry.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:admin_account_id, :action, :target_type, :target_id, :details, :ip_address])
    |> validate_required([:action])
  end
end
