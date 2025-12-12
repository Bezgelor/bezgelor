defmodule BezgelorPortalWeb.Admin.RolesLive do
  @moduledoc """
  Admin LiveView for role management.

  Features:
  - List all roles with permission counts
  - Create new roles
  - Edit role permissions
  - Delete non-protected roles
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Authorization

  @impl true
  def mount(_params, _session, socket) do
    roles = load_roles()

    {:ok,
     assign(socket,
       page_title: "Role Management",
       roles: roles,
       show_create_modal: false,
       create_form: %{"name" => "", "description" => ""}
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Role Management</h1>
          <p class="text-base-content/70">Manage admin roles and permissions</p>
        </div>
        <button
          :if={"roles.create" in get_permission_keys(@current_account)}
          type="button"
          class="btn btn-primary"
          phx-click="show_create_modal"
        >
          <.icon name="hero-plus" class="size-4" />
          Create Role
        </button>
      </div>

      <!-- Roles Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.role_card
          :for={role <- @roles}
          role={role}
          can_edit={"roles.edit" in get_permission_keys(@current_account)}
          can_delete={"roles.delete" in get_permission_keys(@current_account)}
        />
      </div>

      <!-- Create Modal -->
      <.modal :if={@show_create_modal} id="create-role-modal" show on_cancel={JS.push("hide_create_modal")}>
        <:title>Create New Role</:title>
        <form phx-submit="create_role" class="space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Role Name</span>
            </label>
            <input
              type="text"
              name="name"
              value={@create_form["name"]}
              class="input input-bordered"
              placeholder="e.g., moderator, event_host"
              required
            />
            <label class="label">
              <span class="label-text-alt">Use lowercase letters, numbers, and underscores</span>
            </label>
          </div>

          <div class="form-control">
            <label class="label">
              <span class="label-text">Description</span>
            </label>
            <textarea
              name="description"
              class="textarea textarea-bordered"
              placeholder="Describe this role's purpose"
              rows="3"
            >{@create_form["description"]}</textarea>
          </div>

          <div class="modal-action">
            <button type="button" class="btn" phx-click="hide_create_modal">Cancel</button>
            <button type="submit" class="btn btn-primary">Create Role</button>
          </div>
        </form>
      </.modal>
    </div>
    """
  end

  attr :role, :map, required: true
  attr :can_edit, :boolean, default: false
  attr :can_delete, :boolean, default: false

  defp role_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body">
        <div class="flex items-start justify-between">
          <div>
            <h3 class="card-title text-lg">
              {@role.name}
              <span :if={@role.protected} class="badge badge-warning badge-sm">Protected</span>
            </h3>
            <p class="text-sm text-base-content/70 mt-1">
              {@role.description || "No description"}
            </p>
          </div>
        </div>

        <div class="mt-4 space-y-2">
          <div class="flex items-center gap-2 text-sm">
            <.icon name="hero-key" class="size-4 text-base-content/50" />
            <span>{@role.permission_count} permissions</span>
          </div>
          <div class="flex items-center gap-2 text-sm">
            <.icon name="hero-users" class="size-4 text-base-content/50" />
            <span>{@role.user_count} users</span>
          </div>
        </div>

        <div class="card-actions justify-end mt-4">
          <.link
            :if={@can_edit}
            navigate={~p"/admin/roles/#{@role.id}/edit"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-pencil" class="size-4" />
            Edit
          </.link>
          <button
            :if={@can_delete && !@role.protected}
            type="button"
            class="btn btn-ghost btn-sm text-error"
            phx-click="delete_role"
            phx-value-id={@role.id}
            data-confirm={"Are you sure you want to delete the \"#{@role.name}\" role?"}
          >
            <.icon name="hero-trash" class="size-4" />
            Delete
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("show_create_modal", _, socket) do
    {:noreply, assign(socket, show_create_modal: true)}
  end

  @impl true
  def handle_event("hide_create_modal", _, socket) do
    {:noreply, assign(socket, show_create_modal: false, create_form: %{"name" => "", "description" => ""})}
  end

  @impl true
  def handle_event("create_role", params, socket) do
    admin = socket.assigns.current_account

    attrs = %{
      name: params["name"],
      description: params["description"]
    }

    case Authorization.create_role(attrs) do
      {:ok, role} ->
        Authorization.log_action(admin, "role.create", "role", role.id, %{name: role.name})

        {:noreply,
         socket
         |> put_flash(:info, "Role \"#{role.name}\" created")
         |> assign(
           roles: load_roles(),
           show_create_modal: false,
           create_form: %{"name" => "", "description" => ""}
         )}

      {:error, changeset} ->
        error = format_changeset_error(changeset)
        {:noreply, put_flash(socket, :error, "Failed to create role: #{error}")}
    end
  end

  @impl true
  def handle_event("delete_role", %{"id" => id_str}, socket) do
    admin = socket.assigns.current_account
    role_id = String.to_integer(id_str)

    case Authorization.get_role(role_id) do
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Role not found")}

      {:ok, role} ->
        case Authorization.delete_role(role) do
          {:ok, _} ->
            Authorization.log_action(admin, "role.delete", "role", role.id, %{name: role.name})

            {:noreply,
             socket
             |> put_flash(:info, "Role \"#{role.name}\" deleted")
             |> assign(roles: load_roles())}

          {:error, :protected} ->
            {:noreply, put_flash(socket, :error, "Cannot delete protected roles")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to delete role")}
        end
    end
  end

  # Helpers

  defp load_roles do
    Authorization.list_roles()
    |> Enum.map(fn role ->
      permissions = Authorization.get_role_permissions(role)
      users = count_role_users(role.id)

      %{
        id: role.id,
        name: role.name,
        description: role.description,
        protected: role.protected,
        permission_count: length(permissions),
        user_count: users
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp count_role_users(role_id) do
    # Query count of users with this role
    import Ecto.Query
    alias BezgelorDb.Schema.AccountRole
    alias BezgelorDb.Repo

    AccountRole
    |> where([ar], ar.role_id == ^role_id)
    |> Repo.aggregate(:count)
  end

  defp get_permission_keys(account) do
    Authorization.get_account_permissions(account)
    |> Enum.map(& &1.key)
  end

  defp format_changeset_error(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
