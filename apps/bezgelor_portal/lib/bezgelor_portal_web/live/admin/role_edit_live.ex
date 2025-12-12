defmodule BezgelorPortalWeb.Admin.RoleEditLive do
  @moduledoc """
  Admin LiveView for editing role permissions.

  Features:
  - Edit role name and description
  - Permission checkbox grid by category
  - Save permissions
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Authorization

  @impl true
  def mount(%{"id" => id_str}, _session, socket) do
    case load_role(id_str) do
      {:ok, role, permissions, all_permissions} ->
        enabled_keys = MapSet.new(Enum.map(permissions, & &1.key))

        {:ok,
         assign(socket,
           page_title: "Edit Role: #{role.name}",
           role: role,
           enabled_permissions: enabled_keys,
           all_permissions: all_permissions,
           form: %{"name" => role.name, "description" => role.description || ""},
           has_changes: false
         ),
         layout: {BezgelorPortalWeb.Layouts, :admin}}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "Role not found")
         |> push_navigate(to: ~p"/admin/roles"),
         layout: {BezgelorPortalWeb.Layouts, :admin}}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <.link navigate={~p"/admin/roles"} class="text-sm text-base-content/70 hover:text-primary flex items-center gap-1">
            <.icon name="hero-arrow-left" class="size-4" />
            Back to Roles
          </.link>
          <h1 class="text-2xl font-bold mt-2 flex items-center gap-3">
            Edit Role: {@role.name}
            <span :if={@role.protected} class="badge badge-warning">Protected</span>
          </h1>
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            class={"btn btn-primary #{unless @has_changes, do: "btn-disabled"}"}
            phx-click="save"
            disabled={!@has_changes}
          >
            <.icon name="hero-check" class="size-4" />
            Save Changes
          </button>
        </div>
      </div>

      <!-- Role Info -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Role Information</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-2">
            <div class="form-control">
              <label class="label">
                <span class="label-text">Name</span>
              </label>
              <input
                type="text"
                value={@form["name"]}
                class="input input-bordered"
                phx-blur="update_name"
                phx-value-name={@form["name"]}
                disabled={@role.protected}
              />
            </div>
            <div class="form-control">
              <label class="label">
                <span class="label-text">Description</span>
              </label>
              <input
                type="text"
                value={@form["description"]}
                class="input input-bordered"
                phx-blur="update_description"
                phx-value-description={@form["description"]}
              />
            </div>
          </div>
        </div>
      </div>

      <!-- Permissions -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <div class="flex items-center justify-between mb-4">
            <h2 class="card-title">Permissions</h2>
            <div class="flex gap-2">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="select_all">
                Select All
              </button>
              <button type="button" class="btn btn-ghost btn-sm" phx-click="deselect_all">
                Deselect All
              </button>
            </div>
          </div>

          <div class="space-y-6">
            <%= for {category, permissions} <- @all_permissions do %>
              <div>
                <h3 class="font-semibold text-lg mb-3 capitalize">
                  {format_category(category)}
                </h3>
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
                  <%= for perm <- permissions do %>
                    <label class="flex items-start gap-3 p-3 rounded-lg hover:bg-base-200 cursor-pointer">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-primary mt-0.5"
                        checked={MapSet.member?(@enabled_permissions, perm.key)}
                        phx-click="toggle_permission"
                        phx-value-key={perm.key}
                      />
                      <div>
                        <div class="font-medium text-sm">{perm.key}</div>
                        <div class="text-xs text-base-content/60">{perm.description}</div>
                      </div>
                    </label>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <div class="mt-6 flex items-center gap-2 text-sm text-base-content/70">
            <.icon name="hero-information-circle" class="size-4" />
            <span>{MapSet.size(@enabled_permissions)} permissions selected</span>
          </div>
        </div>
      </div>

      <!-- Save Button (bottom) -->
      <div class="flex justify-end">
        <button
          type="button"
          class={"btn btn-primary btn-lg #{unless @has_changes, do: "btn-disabled"}"}
          phx-click="save"
          disabled={!@has_changes}
        >
          <.icon name="hero-check" class="size-5" />
          Save Changes
        </button>
      </div>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("toggle_permission", %{"key" => key}, socket) do
    enabled = socket.assigns.enabled_permissions

    new_enabled =
      if MapSet.member?(enabled, key) do
        MapSet.delete(enabled, key)
      else
        MapSet.put(enabled, key)
      end

    {:noreply, assign(socket, enabled_permissions: new_enabled, has_changes: true)}
  end

  @impl true
  def handle_event("select_all", _, socket) do
    all_keys =
      socket.assigns.all_permissions
      |> Enum.flat_map(fn {_cat, perms} -> Enum.map(perms, & &1.key) end)
      |> MapSet.new()

    {:noreply, assign(socket, enabled_permissions: all_keys, has_changes: true)}
  end

  @impl true
  def handle_event("deselect_all", _, socket) do
    {:noreply, assign(socket, enabled_permissions: MapSet.new(), has_changes: true)}
  end

  @impl true
  def handle_event("update_name", %{"value" => name}, socket) do
    form = Map.put(socket.assigns.form, "name", name)
    {:noreply, assign(socket, form: form, has_changes: true)}
  end

  @impl true
  def handle_event("update_description", %{"value" => desc}, socket) do
    form = Map.put(socket.assigns.form, "description", desc)
    {:noreply, assign(socket, form: form, has_changes: true)}
  end

  @impl true
  def handle_event("save", _, socket) do
    admin = socket.assigns.current_account
    role = socket.assigns.role
    form = socket.assigns.form
    enabled_keys = socket.assigns.enabled_permissions

    # Get permission IDs from keys
    permission_ids =
      socket.assigns.all_permissions
      |> Enum.flat_map(fn {_cat, perms} -> perms end)
      |> Enum.filter(fn p -> MapSet.member?(enabled_keys, p.key) end)
      |> Enum.map(& &1.id)

    # Update role info if changed and not protected
    role =
      if !role.protected && (form["name"] != role.name || form["description"] != role.description) do
        case Authorization.update_role(role, %{name: form["name"], description: form["description"]}) do
          {:ok, updated} -> updated
          {:error, _} -> role
        end
      else
        role
      end

    # Update permissions
    case Authorization.set_role_permissions(role, permission_ids) do
      {:ok, _} ->
        Authorization.log_action(admin, "role.update", "role", role.id, %{
          name: role.name,
          permission_count: length(permission_ids)
        })

        {:noreply,
         socket
         |> put_flash(:info, "Role \"#{role.name}\" updated successfully")
         |> assign(role: role, has_changes: false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update role permissions")}
    end
  end

  # Helpers

  defp load_role(id_str) do
    case Integer.parse(id_str) do
      {id, ""} ->
        case Authorization.get_role(id) do
          {:ok, role} ->
            permissions = Authorization.get_role_permissions(role)
            all_permissions = Authorization.list_permissions_by_category()
            {:ok, role, permissions, all_permissions}

          {:error, :not_found} ->
            {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp format_category(category) do
    category
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
