defmodule BezgelorPortalWeb.Admin.AdminDashboardLive do
  @moduledoc """
  Admin Dashboard LiveView - main landing page for admin panel.

  Shows:
  - Quick stats (accounts, characters, server status)
  - Recent admin actions from audit log
  - Links to common admin actions
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.{Accounts, Authorization}

  @impl true
  def mount(_params, _session, socket) do
    account = socket.assigns.current_account
    permissions = Authorization.get_account_permissions(account)
    permission_keys = Enum.map(permissions, & &1.key)

    # Load stats
    stats = load_stats()

    # Load recent audit log entries (if user has permission)
    recent_actions =
      if "admin.view_audit_log" in permission_keys do
        Authorization.list_audit_log(limit: 10)
      else
        []
      end

    {:ok,
     assign(socket,
       page_title: nil,
       permissions: permission_keys,
       stats: stats,
       recent_actions: recent_actions
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold">Admin Dashboard</h1>
      </div>

      <!-- Stats Cards -->
      <div class="stats shadow w-full bg-base-100">
        <div class="stat">
          <div class="stat-figure text-primary">
            <.icon name="hero-users" class="size-8" />
          </div>
          <div class="stat-title">Total Accounts</div>
          <div class="stat-value text-primary">{format_stat(@stats.account_count)}</div>
          <div class="stat-desc">Registered users</div>
        </div>

        <div class="stat">
          <div class="stat-figure text-secondary">
            <.icon name="hero-user-group" class="size-8" />
          </div>
          <div class="stat-title">Total Characters</div>
          <div class="stat-value text-secondary">{format_stat(@stats.character_count)}</div>
          <div class="stat-desc">Created characters</div>
        </div>

        <div class="stat">
          <div class="stat-figure text-info">
            <.icon name="hero-globe-alt" class="size-8" />
          </div>
          <div class="stat-title">Online Players</div>
          <div class="stat-value text-info">--</div>
          <div class="stat-desc">Real-time tracking coming soon</div>
        </div>

        <div class="stat">
          <div class="stat-figure text-success">
            <.icon name="hero-server" class="size-8" />
          </div>
          <div class="stat-title">Server Status</div>
          <div class="stat-value text-success">Online</div>
          <div class="stat-desc">Portal operational</div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Quick Actions -->
        <div class="lg:col-span-2 space-y-6">
          <h2 class="text-xl font-semibold">Quick Actions</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.admin_card
              :if={"users.view" in @permissions}
              title="User Management"
              description="Search and manage player accounts"
              href="/admin/users"
              icon="hero-users"
            />

            <.admin_card
              :if={"characters.view" in @permissions}
              title="Character Management"
              description="View and manage characters"
              href="/admin/characters"
              icon="hero-user-group"
            />

            <.admin_card
              :if={"events.broadcast_message" in @permissions}
              title="Broadcast Message"
              description="Send server-wide announcements"
              href="/admin/events/broadcast"
              icon="hero-megaphone"
            />

            <.admin_card
              :if={"admin.view_audit_log" in @permissions}
              title="Audit Log"
              description="View admin action history"
              href="/admin/audit-log"
              icon="hero-document-text"
            />

            <.admin_card
              :if={"admin.manage_roles" in @permissions}
              title="Role Management"
              description="Manage roles and permissions"
              href="/admin/roles"
              icon="hero-shield-check"
            />

            <.admin_card
              :if={"server.view_logs" in @permissions}
              title="Server Logs"
              description="View server logs and errors"
              href="/admin/server/logs"
              icon="hero-command-line"
            />
          </div>
        </div>

        <!-- Recent Admin Actions -->
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <h2 class="text-xl font-semibold">Recent Activity</h2>
            <.link
              :if={"admin.view_audit_log" in @permissions}
              href="/admin/audit-log"
              class="text-sm link link-primary"
            >
              View all
            </.link>
          </div>

          <div class="card bg-base-100 shadow">
            <div class="card-body p-4">
              <%= if Enum.empty?(@recent_actions) do %>
                <div class="text-center py-6 text-base-content/50">
                  <.icon name="hero-clock" class="size-8 mx-auto mb-2" />
                  <p class="text-sm">No recent admin actions</p>
                </div>
              <% else %>
                <ul class="space-y-3">
                  <li :for={action <- @recent_actions} class="flex items-start gap-3 text-sm">
                    <div class={"p-1.5 rounded-full #{action_color(action.action)}"}>
                      <.icon name={action_icon(action.action)} class="size-3" />
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="font-medium truncate">{format_action(action.action)}</p>
                      <p class="text-xs text-base-content/50">
                        {format_relative_time(action.inserted_at)}
                      </p>
                    </div>
                  </li>
                </ul>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :href, :string, required: true
  attr :icon, :string, required: true

  defp admin_card(assigns) do
    ~H"""
    <.link href={@href} class="card bg-base-100 shadow-md hover:shadow-lg transition-shadow">
      <div class="card-body p-4">
        <div class="flex items-center gap-3">
          <div class="p-2.5 rounded-lg bg-primary/10 text-primary">
            <.icon name={@icon} class="size-5" />
          </div>
          <div>
            <h3 class="font-semibold">{@title}</h3>
            <p class="text-xs text-base-content/70">{@description}</p>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  # Load dashboard stats
  defp load_stats do
    %{
      account_count: Accounts.count_accounts(),
      character_count: Accounts.count_characters()
    }
  end

  # Format stat for display
  defp format_stat(nil), do: "--"
  defp format_stat(n) when is_integer(n), do: format_number(n)

  defp format_number(n) when n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: to_string(n)

  # Format action name for display
  defp format_action(action) when is_binary(action) do
    action
    |> String.replace(".", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  # Get icon for action type
  defp action_icon(action) do
    cond do
      String.contains?(action, "ban") -> "hero-no-symbol"
      String.contains?(action, "unban") -> "hero-check-circle"
      String.contains?(action, "role") -> "hero-shield-check"
      String.contains?(action, "user") -> "hero-user"
      String.contains?(action, "character") -> "hero-user-group"
      String.contains?(action, "item") -> "hero-gift"
      String.contains?(action, "currency") -> "hero-currency-dollar"
      true -> "hero-cog-6-tooth"
    end
  end

  # Get color class for action type
  defp action_color(action) do
    cond do
      String.contains?(action, "ban") -> "bg-error/20 text-error"
      String.contains?(action, "unban") -> "bg-success/20 text-success"
      String.contains?(action, "delete") -> "bg-error/20 text-error"
      String.contains?(action, "grant") -> "bg-success/20 text-success"
      String.contains?(action, "create") -> "bg-info/20 text-info"
      true -> "bg-base-300 text-base-content"
    end
  end

  # Format relative time
  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end
