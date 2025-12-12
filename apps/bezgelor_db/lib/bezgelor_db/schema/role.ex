defmodule BezgelorDb.Schema.Role do
  @moduledoc """
  Database schema for RBAC roles.

  Roles group permissions together for assignment to accounts.
  Protected roles (Moderator, Admin, Super Admin) cannot be deleted.

  ## Fields

  - `name` - Unique role name (e.g., "Moderator", "Admin")
  - `description` - Human-readable description of the role
  - `protected` - If true, role cannot be deleted (system roles)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          protected: boolean(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "roles" do
    field :name, :string
    field :description, :string
    field :protected, :boolean, default: false

    has_many :role_permissions, BezgelorDb.Schema.RolePermission
    many_to_many :permissions, BezgelorDb.Schema.Permission, join_through: "role_permissions"
    many_to_many :accounts, BezgelorDb.Schema.Account, join_through: "account_roles"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a role.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :description, :protected])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:name)
  end
end
