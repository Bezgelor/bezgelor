defmodule BezgelorDb.Schema.AccountRole do
  @moduledoc """
  Join schema linking accounts to roles with assignment tracking.

  Tracks who assigned the role and when for audit purposes.

  ## Fields

  - `account_id` - The account receiving the role
  - `role_id` - The role being assigned
  - `assigned_by` - Account ID of the admin who assigned (nullable)
  - `assigned_at` - When the role was assigned
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          account_id: integer() | nil,
          role_id: integer() | nil,
          assigned_by: integer() | nil,
          assigned_at: DateTime.t() | nil
        }

  @primary_key false
  schema "account_roles" do
    belongs_to(:account, BezgelorDb.Schema.Account)
    belongs_to(:role, BezgelorDb.Schema.Role)
    belongs_to(:assigner, BezgelorDb.Schema.Account, foreign_key: :assigned_by)

    field(:assigned_at, :utc_datetime)
  end

  @doc """
  Changeset for creating an account role assignment.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(account_role, attrs) do
    account_role
    |> cast(attrs, [:account_id, :role_id, :assigned_by, :assigned_at])
    |> validate_required([:account_id, :role_id, :assigned_at])
    |> unique_constraint([:account_id, :role_id])
  end
end
