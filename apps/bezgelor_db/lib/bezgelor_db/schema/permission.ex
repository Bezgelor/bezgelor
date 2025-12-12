defmodule BezgelorDb.Schema.Permission do
  @moduledoc """
  Database schema for RBAC permissions.

  Permissions are seeded and define granular access rights that can be
  assigned to roles. They are immutable at runtime (no changeset needed).

  ## Fields

  - `key` - Unique identifier (e.g., "users.view", "characters.edit")
  - `category` - Grouping category (e.g., "user_management", "character_management")
  - `description` - Human-readable description of what the permission allows
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          key: String.t() | nil,
          category: String.t() | nil,
          description: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "permissions" do
    field :key, :string
    field :category, :string
    field :description, :string

    many_to_many :roles, BezgelorDb.Schema.Role, join_through: "role_permissions"

    timestamps(type: :utc_datetime)
  end
end
