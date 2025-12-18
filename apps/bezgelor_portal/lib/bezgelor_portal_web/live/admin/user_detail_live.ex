defmodule BezgelorPortalWeb.Admin.UserDetailLive do
  @dialyzer :no_match

  @moduledoc """
  Admin LiveView for viewing and managing individual user accounts.

  Features:
  - Account info display
  - Character list
  - Password reset
  - Ban/suspend/unban
  - Role management
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.{Accounts, Authorization, Characters}
  alias BezgelorPortal.GameData

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    admin = socket.assigns.current_account
    permissions = Authorization.get_account_permissions(admin)
    permission_keys = Enum.map(permissions, & &1.key)

    case load_user(id) do
      {:ok, user} ->
        {:ok,
         assign(socket,
           page_title: user.email,
           parent_path: ~p"/admin/users",
           parent_label: "Users",
           user: user,
           characters: Characters.list_characters(user.id),
           roles: Authorization.list_roles(),
           user_roles: Authorization.get_account_roles(user),
           active_suspension: Accounts.get_active_suspension(user),
           permissions: permission_keys,
           show_ban_modal: false,
           show_role_modal: false,
           ban_form: %{"reason" => "", "duration" => "7", "permanent" => false}
         ),
         layout: {BezgelorPortalWeb.Layouts, :admin}}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "User not found")
         |> push_navigate(to: ~p"/admin/users"),
         layout: {BezgelorPortalWeb.Layouts, :admin}}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold">{@user.email}</h1>
          <%= if @user.email_verified_at do %>
            <span class="badge badge-success gap-1">
              <.icon name="hero-check-badge-micro" class="size-3" />
              Verified
            </span>
          <% end %>
          <.status_badges user={@user} active_suspension={@active_suspension} />
        </div>
      </div>

      <!-- Account Info and Roles/Actions -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Account Info Card (Left) -->
        <div class="card bg-base-100 shadow">
          <div class="card-body">
            <h2 class="card-title">Account Information</h2>
            <div class="grid grid-cols-2 gap-4 mt-4">
              <div>
                <span class="text-sm text-base-content/50">Account ID</span>
                <p class="font-medium font-mono">{@user.id}</p>
              </div>
              <div>
                <span class="text-sm text-base-content/50">Registered</span>
                <p class="font-medium">{format_datetime(@user.inserted_at)}</p>
              </div>
              <div>
                <span class="text-sm text-base-content/50">Email Verified</span>
                <p class="font-medium">
                  <%= if @user.email_verified_at do %>
                    <span class="text-success">{format_datetime(@user.email_verified_at)}</span>
                  <% else %>
                    <span class="text-warning">Not verified</span>
                  <% end %>
                </p>
              </div>
              <div>
                <span class="text-sm text-base-content/50">Two-Factor Auth</span>
                <p class="font-medium">
                  <%= if @user.totp_enabled_at do %>
                    <span class="text-success">Enabled {format_datetime(@user.totp_enabled_at)}</span>
                  <% else %>
                    <span class="text-base-content/70">Not enabled</span>
                  <% end %>
                </p>
              </div>
              <div>
                <span class="text-sm text-base-content/50">Discord Link</span>
                <p class="font-medium">
                  <%= if @user.discord_id do %>
                    <span class="text-primary">{@user.discord_username}</span>
                  <% else %>
                    <span class="text-base-content/70">Not linked</span>
                  <% end %>
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Roles and Actions (Right) -->
        <div class="space-y-6">
          <!-- Roles Card -->
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <div class="flex items-center justify-between">
                <h2 class="card-title">Roles</h2>
                <button
                  :if={"admin.manage_roles" in @permissions}
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click="show_role_modal"
                >
                  <.icon name="hero-pencil" class="size-4" />
                  Edit
                </button>
              </div>
              <div class="mt-2">
                <%= if Enum.empty?(@user_roles) do %>
                  <p class="text-base-content/50 text-sm">No roles assigned</p>
                <% else %>
                  <div class="flex flex-wrap gap-2">
                    <span :for={role <- @user_roles} class="badge badge-lg badge-primary gap-1">
                      <.icon name="hero-shield-check-micro" class="size-3" />
                      {role.name}
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Actions Card -->
          <div class="card bg-base-100 shadow">
            <div class="card-body">
              <h2 class="card-title">Actions</h2>
              <div class="flex flex-col gap-2 mt-2">
                <button
                  :if={"users.reset_password" in @permissions}
                  type="button"
                  class="btn btn-outline btn-sm justify-start"
                  phx-click="reset_password"
                  data-confirm="Are you sure you want to reset this user's password? They will receive an email with a reset link."
                >
                  <.icon name="hero-key" class="size-4" />
                  Reset Password
                </button>

                <%= if @active_suspension do %>
                  <button
                    :if={"users.unban" in @permissions}
                    type="button"
                    class="btn btn-success btn-sm justify-start"
                    phx-click="unban"
                    data-confirm="Are you sure you want to remove the ban/suspension from this account?"
                  >
                    <.icon name="hero-check-circle" class="size-4" />
                    Remove Ban
                  </button>
                <% else %>
                  <button
                    :if={"users.ban" in @permissions}
                    type="button"
                    class="btn btn-error btn-sm justify-start"
                    phx-click="show_ban_modal"
                  >
                    <.icon name="hero-no-symbol" class="size-4" />
                    Ban/Suspend
                  </button>
                <% end %>

                <%= if @user.deleted_at do %>
                  <button
                    :if={"users.restore" in @permissions}
                    type="button"
                    class="btn btn-warning btn-sm justify-start"
                    phx-click="restore_account"
                    data-confirm="Are you sure you want to restore this deleted account?"
                  >
                    <.icon name="hero-arrow-uturn-left" class="size-4" />
                    Restore Account
                  </button>
                <% else %>
                  <button
                    :if={"users.delete" in @permissions}
                    type="button"
                    class="btn btn-error btn-outline btn-sm justify-start"
                    phx-click="delete_account"
                    data-confirm="Are you sure you want to delete this account? This is a soft delete and can be restored."
                  >
                    <.icon name="hero-trash" class="size-4" />
                    Delete Account
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Suspension Info -->
      <div :if={@active_suspension} class="alert alert-error">
        <.icon name="hero-exclamation-triangle" class="size-6" />
        <div>
          <h3 class="font-bold">Account is {if is_nil(@active_suspension.end_time), do: "Permanently Banned", else: "Suspended"}</h3>
          <div class="text-sm">
            <p><strong>Reason:</strong> {@active_suspension.reason}</p>
            <p><strong>Since:</strong> {format_datetime(@active_suspension.start_time)}</p>
            <p :if={@active_suspension.end_time}>
              <strong>Until:</strong> {format_datetime(@active_suspension.end_time)}
            </p>
          </div>
        </div>
      </div>

      <!-- Characters Card -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Characters ({length(@characters)})</h2>
          <%= if Enum.empty?(@characters) do %>
            <p class="text-base-content/50">No characters</p>
          <% else %>
            <div class="overflow-x-auto mt-4">
              <table class="table">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Level</th>
                    <th>Class</th>
                    <th>Race</th>
                    <th>Last Online</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={char <- @characters} class="hover">
                    <td class="font-semibold">{char.name}</td>
                    <td>{char.level}</td>
                    <td>
                      <span style={"color: #{GameData.class_color(char.class)}"}>
                        {GameData.class_name(char.class)}
                      </span>
                    </td>
                    <td>{GameData.race_name(char.race)}</td>
                    <td class="text-sm text-base-content/70">
                      {GameData.format_relative_time(char.last_online)}
                    </td>
                    <td>
                      <.link navigate={~p"/admin/characters/#{char.id}"} class="btn btn-ghost btn-xs">
                        View
                      </.link>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Ban Modal -->
      <.modal :if={@show_ban_modal} id="ban-modal" show on_cancel={JS.push("hide_ban_modal")}>
        <:title>Ban / Suspend Account</:title>
        <form phx-submit="ban_account" class="space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text">Reason</span>
            </label>
            <textarea
              name="reason"
              class="textarea textarea-bordered"
              placeholder="Enter reason for ban/suspension..."
              required
            >{@ban_form["reason"]}</textarea>
          </div>

          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-2">
              <input
                type="checkbox"
                name="permanent"
                class="checkbox"
                checked={@ban_form["permanent"]}
                phx-click="toggle_permanent_ban"
              />
              <span class="label-text">Permanent ban</span>
            </label>
          </div>

          <div :if={!@ban_form["permanent"]} class="form-control">
            <label class="label">
              <span class="label-text">Duration (days)</span>
            </label>
            <select name="duration" class="select select-bordered">
              <option value="1" selected={@ban_form["duration"] == "1"}>1 day</option>
              <option value="3" selected={@ban_form["duration"] == "3"}>3 days</option>
              <option value="7" selected={@ban_form["duration"] == "7"}>7 days</option>
              <option value="14" selected={@ban_form["duration"] == "14"}>14 days</option>
              <option value="30" selected={@ban_form["duration"] == "30"}>30 days</option>
              <option value="90" selected={@ban_form["duration"] == "90"}>90 days</option>
            </select>
          </div>

          <div class="modal-action">
            <button type="button" class="btn" phx-click="hide_ban_modal">Cancel</button>
            <button type="submit" class="btn btn-error">
              <%= if @ban_form["permanent"] do %>
                Permanently Ban
              <% else %>
                Suspend Account
              <% end %>
            </button>
          </div>
        </form>
      </.modal>

      <!-- Role Modal -->
      <.modal :if={@show_role_modal} id="role-modal" show on_cancel={JS.push("hide_role_modal")}>
        <:title>Manage Roles</:title>
        <div class="space-y-4">
          <p class="text-sm text-base-content/70">
            Select roles to assign to this user. Users must have TOTP enabled to receive admin roles.
          </p>

          <div class="space-y-2">
            <div :for={role <- @roles} class="form-control">
              <label class="label cursor-pointer justify-start gap-3">
                <input
                  type="checkbox"
                  class="checkbox"
                  checked={role_assigned?(@user_roles, role)}
                  phx-click="toggle_role"
                  phx-value-role-id={role.id}
                />
                <div>
                  <span class="label-text font-medium">{role.name}</span>
                  <p :if={role.description} class="text-xs text-base-content/50">{role.description}</p>
                </div>
              </label>
            </div>
          </div>

          <div class="modal-action">
            <button type="button" class="btn" phx-click="hide_role_modal">Done</button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :active_suspension, :any, required: true

  defp status_badges(assigns) do
    ~H"""
    <div class="flex gap-2">
      <%= if @user.deleted_at do %>
        <span class="badge badge-error badge-lg">Deleted</span>
      <% end %>
      <%= if @active_suspension do %>
        <%= if is_nil(@active_suspension.end_time) do %>
          <span class="badge badge-error badge-lg">Permanently Banned</span>
        <% else %>
          <span class="badge badge-warning badge-lg">Suspended</span>
        <% end %>
      <% end %>
      <%= if !@user.email_verified_at do %>
        <span class="badge badge-warning badge-lg">Unverified</span>
      <% end %>
    </div>
    """
  end

  # Event handlers

  @impl true
  def handle_event("show_ban_modal", _, socket) do
    {:noreply, assign(socket, show_ban_modal: true)}
  end

  @impl true
  def handle_event("hide_ban_modal", _, socket) do
    {:noreply, assign(socket, show_ban_modal: false)}
  end

  @impl true
  def handle_event("toggle_permanent_ban", _, socket) do
    ban_form = Map.update!(socket.assigns.ban_form, "permanent", &(!&1))
    {:noreply, assign(socket, ban_form: ban_form)}
  end

  @impl true
  def handle_event("ban_account", %{"reason" => reason} = params, socket) do
    admin = socket.assigns.current_account
    user = socket.assigns.user

    duration_days =
      if params["permanent"] do
        nil  # Permanent ban
      else
        String.to_integer(params["duration"])
      end

    case Accounts.create_suspension(user, reason, duration_days) do
      {:ok, _suspension} ->
        # Log the action
        action = if duration_days, do: "user.suspend", else: "user.ban"
        Authorization.log_action(admin, action, "account", user.id, %{
          reason: reason,
          duration_days: duration_days
        })

        {:noreply,
         socket
         |> put_flash(:info, "Account #{if duration_days, do: "suspended", else: "banned"} successfully")
         |> assign(
           active_suspension: Accounts.get_active_suspension(user),
           show_ban_modal: false,
           ban_form: %{"reason" => "", "duration" => "7", "permanent" => false}
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to ban/suspend account")}
    end
  end

  @impl true
  def handle_event("unban", _, socket) do
    admin = socket.assigns.current_account
    user = socket.assigns.user

    case socket.assigns.active_suspension do
      nil ->
        {:noreply, socket}

      suspension ->
        case Accounts.remove_suspension(suspension) do
          {:ok, _} ->
            Authorization.log_action(admin, "user.unban", "account", user.id, %{
              original_reason: suspension.reason
            })

            {:noreply,
             socket
             |> put_flash(:info, "Ban/suspension removed successfully")
             |> assign(active_suspension: nil)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove ban/suspension")}
        end
    end
  end

  @impl true
  def handle_event("reset_password", _, socket) do
    admin = socket.assigns.current_account
    user = socket.assigns.user

    # Send password reset email to user
    case BezgelorPortal.Notifier.deliver_password_reset_email(user) do
      {:ok, _} ->
        Authorization.log_action(admin, "user.reset_password", "account", user.id, %{
          email_sent_to: user.email
        })

        {:noreply,
         socket
         |> put_flash(:info, "Password reset email sent to #{user.email}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send password reset email: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_account", _, socket) do
    admin = socket.assigns.current_account
    user = socket.assigns.user

    case Accounts.soft_delete_account(user) do
      {:ok, updated_user} ->
        Authorization.log_action(admin, "user.delete", "account", user.id, %{})

        {:noreply,
         socket
         |> put_flash(:info, "Account deleted (soft delete)")
         |> assign(user: updated_user)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete account")}
    end
  end

  @impl true
  def handle_event("restore_account", _, socket) do
    admin = socket.assigns.current_account
    user = socket.assigns.user

    case Accounts.restore_account(user) do
      {:ok, updated_user} ->
        Authorization.log_action(admin, "user.restore", "account", user.id, %{})

        {:noreply,
         socket
         |> put_flash(:info, "Account restored")
         |> assign(user: updated_user)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to restore account")}
    end
  end

  @impl true
  def handle_event("show_role_modal", _, socket) do
    {:noreply, assign(socket, show_role_modal: true)}
  end

  @impl true
  def handle_event("hide_role_modal", _, socket) do
    {:noreply, assign(socket, show_role_modal: false)}
  end

  @impl true
  def handle_event("toggle_role", %{"role-id" => role_id}, socket) do
    admin = socket.assigns.current_account
    user = socket.assigns.user
    role_id = String.to_integer(role_id)

    case Authorization.get_role(role_id) do
      {:ok, role} ->
        if role_assigned?(socket.assigns.user_roles, role) do
          # Remove role
          {:ok, _} = Authorization.remove_role(user, role)

          Authorization.log_action(admin, "user.remove_role", "account", user.id, %{
            role_name: role.name
          })

          {:noreply,
           socket
           |> put_flash(:info, "Role '#{role.name}' removed")
           |> assign(user_roles: Authorization.get_account_roles(user))}
        else
          # Check TOTP requirement for admin roles
          role_has_admin_perms = Enum.any?(role.permissions, fn p ->
            String.starts_with?(p.key, "admin.") or
            String.starts_with?(p.key, "users.") or
            String.starts_with?(p.key, "characters.")
          end)

          if role_has_admin_perms and is_nil(user.totp_enabled_at) do
            {:noreply, put_flash(socket, :error, "User must enable 2FA before receiving admin roles")}
          else
            case Authorization.assign_role(user, role, admin) do
              {:ok, _} ->
                Authorization.log_action(admin, "user.assign_role", "account", user.id, %{
                  role_name: role.name
                })

                {:noreply,
                 socket
                 |> put_flash(:info, "Role '#{role.name}' assigned")
                 |> assign(user_roles: Authorization.get_account_roles(user))}

              {:error, :already_assigned} ->
                {:noreply, put_flash(socket, :info, "Role already assigned")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Failed to assign role")}
            end
          end
        end

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Role not found")}
    end
  end

  # Helpers

  defp load_user(id) do
    case Integer.parse(id) do
      {id_int, ""} ->
        case Accounts.get_account_for_admin(id_int) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp role_assigned?(user_roles, role) do
    Enum.any?(user_roles, &(&1.id == role.id))
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end
end
