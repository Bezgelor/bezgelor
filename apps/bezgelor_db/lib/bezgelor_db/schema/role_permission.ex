defmodule BezgelorDb.Schema.RolePermission do
  @moduledoc """
  Join schema linking roles to permissions.

  This is a simple join table with no additional fields.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          role_id: integer() | nil,
          permission_id: integer() | nil
        }

  @primary_key false
  schema "role_permissions" do
    belongs_to :role, BezgelorDb.Schema.Role
    belongs_to :permission, BezgelorDb.Schema.Permission
  end
end
