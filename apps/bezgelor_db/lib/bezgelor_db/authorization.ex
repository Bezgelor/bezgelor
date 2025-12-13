defmodule BezgelorDb.Authorization do
  @moduledoc """
  Authorization context for RBAC (Role-Based Access Control).

  ## Overview

  This module provides the primary interface for authorization operations:

  - Managing permissions (seeded, read-only)
  - Managing roles (CRUD, permission assignment)
  - Assigning roles to accounts
  - Checking permissions for accounts
  - Audit logging for admin actions

  ## Usage

      # Check if account has permission
      if Authorization.has_permission?(account, "users.ban") do
        # perform action
      end

      # Assign a role
      {:ok, _} = Authorization.assign_role(account, role, admin_account)

      # Log an admin action
      Authorization.log_action(admin, "user.ban", "account", target_id, %{reason: "..."})
  """

  import Ecto.Query

  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Account, Permission, Role, RolePermission, AccountRole, AdminAuditLog}

  # ============================================================================
  # Permission Functions
  # ============================================================================

  @doc """
  List all permissions.

  ## Returns

  List of all permissions ordered by category and key.
  """
  @spec list_permissions() :: [Permission.t()]
  def list_permissions do
    Permission
    |> order_by([p], [p.category, p.key])
    |> Repo.all()
  end

  @doc """
  List permissions grouped by category.

  ## Returns

  Map of category => [permissions]

  ## Example

      %{
        "user_management" => [%Permission{key: "users.view"}, ...],
        "character_management" => [%Permission{key: "characters.edit"}, ...]
      }
  """
  @spec list_permissions_by_category() :: %{String.t() => [Permission.t()]}
  def list_permissions_by_category do
    list_permissions()
    |> Enum.group_by(& &1.category)
  end

  @doc """
  Get a permission by its unique key.

  ## Parameters

  - `key` - The permission key (e.g., "users.ban")

  ## Returns

  - `Permission` struct if found
  - `nil` if not found
  """
  @spec get_permission_by_key(String.t()) :: Permission.t() | nil
  def get_permission_by_key(key) when is_binary(key) do
    Repo.get_by(Permission, key: key)
  end

  # ============================================================================
  # Role Functions
  # ============================================================================

  @doc """
  List all roles with permission counts.

  ## Returns

  List of roles with virtual `permission_count` field populated.
  """
  @spec list_roles() :: [Role.t()]
  def list_roles do
    Role
    |> order_by([r], r.name)
    |> preload(:permissions)
    |> Repo.all()
  end

  @doc """
  Get a role by ID with permissions preloaded.

  ## Parameters

  - `id` - The role ID

  ## Returns

  - `{:ok, role}` if found
  - `{:error, :not_found}` if not found
  """
  @spec get_role(integer()) :: {:ok, Role.t()} | {:error, :not_found}
  def get_role(id) when is_integer(id) do
    case Repo.get(Role, id) |> Repo.preload(:permissions) do
      nil -> {:error, :not_found}
      role -> {:ok, role}
    end
  end

  @doc """
  Get a role by name.

  ## Parameters

  - `name` - The role name

  ## Returns

  - `Role` struct if found
  - `nil` if not found
  """
  @spec get_role_by_name(String.t()) :: Role.t() | nil
  def get_role_by_name(name) when is_binary(name) do
    Repo.get_by(Role, name: name) |> Repo.preload(:permissions)
  end

  @doc """
  Get all permissions for a role.

  ## Parameters

  - `role` - The role struct (permissions will be preloaded if not already)

  ## Returns

  - List of Permission structs
  """
  @spec get_role_permissions(Role.t()) :: [Permission.t()]
  def get_role_permissions(%Role{} = role) do
    role = Repo.preload(role, :permissions)
    role.permissions
  end

  @doc """
  Create a new role.

  ## Parameters

  - `attrs` - Map with `:name`, optional `:description`

  ## Returns

  - `{:ok, role}` on success
  - `{:error, changeset}` on failure
  """
  @spec create_role(map()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def create_role(attrs) do
    %Role{}
    |> Role.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a role's name or description.

  Protected roles can still have their description updated.

  ## Parameters

  - `role` - The role to update
  - `attrs` - Map with `:name` and/or `:description`

  ## Returns

  - `{:ok, role}` on success
  - `{:error, changeset}` on failure
  """
  @spec update_role(Role.t(), map()) :: {:ok, Role.t()} | {:error, Ecto.Changeset.t()}
  def update_role(role, attrs) do
    role
    |> Role.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a role.

  Protected roles cannot be deleted.

  ## Parameters

  - `role` - The role to delete

  ## Returns

  - `{:ok, role}` on success
  - `{:error, :protected}` if role is protected
  - `{:error, changeset}` on other failure
  """
  @spec delete_role(Role.t()) :: {:ok, Role.t()} | {:error, :protected | Ecto.Changeset.t()}
  def delete_role(%Role{protected: true}), do: {:error, :protected}

  def delete_role(role) do
    Repo.delete(role)
  end

  @doc """
  Set the permissions for a role, replacing any existing permissions.

  ## Parameters

  - `role` - The role to update
  - `permission_ids` - List of permission IDs to assign

  ## Returns

  - `{:ok, role}` with permissions preloaded
  - `{:error, reason}` on failure
  """
  @spec set_role_permissions(Role.t(), [integer()]) :: {:ok, Role.t()} | {:error, any()}
  def set_role_permissions(role, permission_ids) when is_list(permission_ids) do
    Repo.transaction(fn ->
      # Delete existing role permissions
      from(rp in RolePermission, where: rp.role_id == ^role.id)
      |> Repo.delete_all()

      # Insert new role permissions
      entries =
        Enum.map(permission_ids, fn permission_id ->
          %{role_id: role.id, permission_id: permission_id}
        end)

      if length(entries) > 0 do
        Repo.insert_all(RolePermission, entries)
      end

      # Return role with fresh permissions
      Repo.preload(role, :permissions, force: true)
    end)
  end

  # ============================================================================
  # Account Role Functions
  # ============================================================================

  @doc """
  Get all roles assigned to an account.

  ## Parameters

  - `account` - The account (or account ID)

  ## Returns

  List of roles with permissions preloaded.
  """
  @spec get_account_roles(Account.t() | integer()) :: [Role.t()]
  def get_account_roles(%Account{id: id}), do: get_account_roles(id)

  def get_account_roles(account_id) when is_integer(account_id) do
    from(r in Role,
      join: ar in AccountRole,
      on: ar.role_id == r.id,
      where: ar.account_id == ^account_id,
      preload: :permissions
    )
    |> Repo.all()
  end

  @doc """
  Get all permissions for an account (union of all role permissions).

  ## Parameters

  - `account` - The account (or account ID)

  ## Returns

  List of unique permissions across all roles.
  """
  @spec get_account_permissions(Account.t() | integer()) :: [Permission.t()]
  def get_account_permissions(%Account{id: id}), do: get_account_permissions(id)

  def get_account_permissions(account_id) when is_integer(account_id) do
    from(p in Permission,
      join: rp in RolePermission,
      on: rp.permission_id == p.id,
      join: ar in AccountRole,
      on: ar.role_id == rp.role_id,
      where: ar.account_id == ^account_id,
      distinct: true,
      order_by: [p.category, p.key]
    )
    |> Repo.all()
  end

  @doc """
  Assign a role to an account.

  ## Parameters

  - `account` - The account receiving the role
  - `role` - The role to assign
  - `assigner` - The admin account assigning the role (optional)

  ## Returns

  - `{:ok, account_role}` on success
  - `{:error, :already_assigned}` if role already assigned
  - `{:error, changeset}` on other failure
  """
  @spec assign_role(Account.t(), Role.t(), Account.t() | nil) ::
          {:ok, AccountRole.t()} | {:error, :already_assigned | Ecto.Changeset.t()}
  def assign_role(account, role, assigner \\ nil) do
    attrs = %{
      account_id: account.id,
      role_id: role.id,
      assigned_by: if(assigner, do: assigner.id),
      assigned_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case %AccountRole{} |> AccountRole.changeset(attrs) |> Repo.insert() do
      {:ok, account_role} -> {:ok, account_role}
      {:error, %{errors: [account_id: _]}} -> {:error, :already_assigned}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Remove a role from an account.

  ## Parameters

  - `account` - The account
  - `role` - The role to remove

  ## Returns

  - `{:ok, count}` with number of removed assignments (0 or 1)
  """
  @spec remove_role(Account.t(), Role.t()) :: {:ok, integer()}
  def remove_role(account, role) do
    {count, _} =
      from(ar in AccountRole,
        where: ar.account_id == ^account.id and ar.role_id == ^role.id
      )
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc """
  Check if an account has a specific permission.

  ## Parameters

  - `account` - The account (or account ID)
  - `permission_key` - The permission key to check (e.g., "users.ban")

  ## Returns

  `true` if the account has the permission, `false` otherwise.

  ## Example

      if Authorization.has_permission?(account, "users.ban") do
        # can ban users
      end
  """
  @spec has_permission?(Account.t() | integer(), String.t()) :: boolean()
  def has_permission?(%Account{id: id}, permission_key), do: has_permission?(id, permission_key)

  def has_permission?(account_id, permission_key) when is_integer(account_id) and is_binary(permission_key) do
    query =
      from(p in Permission,
        join: rp in RolePermission,
        on: rp.permission_id == p.id,
        join: ar in AccountRole,
        on: ar.role_id == rp.role_id,
        where: ar.account_id == ^account_id and p.key == ^permission_key,
        select: count(p.id)
      )

    Repo.one(query) > 0
  end

  @doc """
  Check if an account has any of the given permissions.

  ## Parameters

  - `account` - The account (or account ID)
  - `permission_keys` - List of permission keys to check

  ## Returns

  `true` if the account has at least one of the permissions, `false` otherwise.
  """
  @spec has_any_permission?(Account.t() | integer(), [String.t()]) :: boolean()
  def has_any_permission?(%Account{id: id}, permission_keys), do: has_any_permission?(id, permission_keys)

  def has_any_permission?(account_id, permission_keys) when is_integer(account_id) and is_list(permission_keys) do
    query =
      from(p in Permission,
        join: rp in RolePermission,
        on: rp.permission_id == p.id,
        join: ar in AccountRole,
        on: ar.role_id == rp.role_id,
        where: ar.account_id == ^account_id and p.key in ^permission_keys,
        select: count(p.id)
      )

    Repo.one(query) > 0
  end

  # ============================================================================
  # Audit Log Functions
  # ============================================================================

  @doc """
  Log an admin action.

  ## Parameters

  - `admin` - The admin account performing the action
  - `action` - The action being performed (e.g., "user.ban")
  - `target_type` - Type of target (e.g., "account", "character")
  - `target_id` - ID of the target entity
  - `details` - Map with action-specific details
  - `ip_address` - Optional IP address string

  ## Returns

  - `{:ok, log_entry}` on success
  - `{:error, changeset}` on failure
  """
  @spec log_action(Account.t(), String.t(), String.t() | nil, integer() | nil, map(), String.t() | nil) ::
          {:ok, AdminAuditLog.t()} | {:error, Ecto.Changeset.t()}
  def log_action(admin, action, target_type \\ nil, target_id \\ nil, details \\ %{}, ip_address \\ nil) do
    %AdminAuditLog{}
    |> AdminAuditLog.changeset(%{
      admin_account_id: admin.id,
      action: action,
      target_type: target_type,
      target_id: target_id,
      details: details,
      ip_address: ip_address
    })
    |> Repo.insert()
  end

  @doc """
  Query audit log entries with filters.

  ## Options

  - `:admin_id` - Filter by admin account ID
  - `:action` - Filter by action (exact match or prefix with *)
  - `:target_type` - Filter by target type
  - `:target_id` - Filter by target ID
  - `:from` - Filter entries after this datetime
  - `:to` - Filter entries before this datetime
  - `:limit` - Maximum number of entries to return (default 100)
  - `:offset` - Number of entries to skip (for pagination)

  ## Returns

  List of audit log entries, most recent first.
  """
  @spec list_audit_log(keyword()) :: [AdminAuditLog.t()]
  def list_audit_log(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(log in AdminAuditLog,
        order_by: [desc: log.inserted_at],
        limit: ^limit,
        offset: ^offset,
        preload: [:admin_account]
      )

    query
    |> maybe_filter_by_admin(opts[:admin_id])
    |> maybe_filter_by_action(opts[:action])
    |> maybe_filter_by_target_type(opts[:target_type])
    |> maybe_filter_by_target_id(opts[:target_id])
    |> maybe_filter_by_date_range(opts[:from], opts[:to])
    |> Repo.all()
  end

  defp maybe_filter_by_admin(query, nil), do: query
  defp maybe_filter_by_admin(query, admin_id) do
    from(log in query, where: log.admin_account_id == ^admin_id)
  end

  defp maybe_filter_by_action(query, nil), do: query
  defp maybe_filter_by_action(query, action) do
    if String.ends_with?(action, "*") do
      prefix = String.trim_trailing(action, "*")
      from(log in query, where: like(log.action, ^"#{prefix}%"))
    else
      from(log in query, where: log.action == ^action)
    end
  end

  defp maybe_filter_by_target_type(query, nil), do: query
  defp maybe_filter_by_target_type(query, target_type) do
    from(log in query, where: log.target_type == ^target_type)
  end

  defp maybe_filter_by_target_id(query, nil), do: query
  defp maybe_filter_by_target_id(query, target_id) do
    from(log in query, where: log.target_id == ^target_id)
  end

  defp maybe_filter_by_date_range(query, nil, nil), do: query
  defp maybe_filter_by_date_range(query, from, nil) do
    from(log in query, where: log.inserted_at >= ^from)
  end
  defp maybe_filter_by_date_range(query, nil, to) do
    from(log in query, where: log.inserted_at <= ^to)
  end
  defp maybe_filter_by_date_range(query, from, to) do
    from(log in query, where: log.inserted_at >= ^from and log.inserted_at <= ^to)
  end

  @doc """
  Get audit history for a specific admin account.

  ## Parameters

  - `admin` - The admin account (or account ID)
  - `opts` - Options (same as `list_audit_log/1`)

  ## Returns

  List of audit log entries by this admin.
  """
  @spec get_account_audit_history(Account.t() | integer(), keyword()) :: [AdminAuditLog.t()]
  def get_account_audit_history(admin_or_id, opts \\ [])
  def get_account_audit_history(%Account{id: id}, opts), do: get_account_audit_history(id, opts)

  def get_account_audit_history(admin_id, opts) when is_integer(admin_id) do
    list_audit_log(Keyword.put(opts, :admin_id, admin_id))
  end
end
