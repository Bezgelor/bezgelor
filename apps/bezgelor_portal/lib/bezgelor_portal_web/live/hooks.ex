defmodule BezgelorPortalWeb.Live.Hooks do
  @moduledoc """
  LiveView lifecycle hooks for authentication and authorization.

  ## Usage

  In your LiveView:

      on_mount {BezgelorPortalWeb.Live.Hooks, :require_auth}

  Or in your router for a group of LiveViews:

      live_session :authenticated, on_mount: [{BezgelorPortalWeb.Live.Hooks, :require_auth}] do
        live "/dashboard", DashboardLive
      end

  ## Available Hooks

  - `:fetch_current_account` - Loads the current account if logged in (does not require auth)
  - `:require_auth` - Requires authentication, redirects to login if not authenticated
  - `:require_admin` - Requires authentication AND at least one admin permission AND TOTP enabled
  """

  import Phoenix.LiveView
  import Phoenix.Component
  import Plug.Conn, only: [get_session: 2]

  alias BezgelorDb.{Accounts, Authorization}
  alias BezgelorPortal.TOTP

  @session_key :current_account_id

  @doc """
  Mount callback for fetching current account or requiring authentication.

  - `:fetch_current_account` - Loads the current account if logged in (does not require auth)
  - `:require_auth` - Requires authentication, redirects to login if not authenticated
  - `:require_admin` - Requires authentication AND at least one admin permission
  """
  def on_mount(action, params, session, socket)

  def on_mount(:fetch_current_account, _params, session, socket) do
    socket = assign_current_account(socket, session)
    {:cont, socket}
  end

  def on_mount(:require_auth, _params, session, socket) do
    socket = assign_current_account(socket, session)

    if socket.assigns.current_account do
      socket =
        socket
        |> assign(:has_admin_access, has_admin_access?(socket.assigns.current_account))
        |> assign_server_status()
        |> maybe_schedule_status_refresh()

      {:cont, socket}
    else
      socket =
        socket
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/login")

      {:halt, socket}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    socket = assign_current_account(socket, session)
    account = socket.assigns.current_account

    cond do
      is_nil(account) ->
        socket =
          socket
          |> put_flash(:error, "You must be logged in to access this page.")
          |> redirect(to: "/login")

        {:halt, socket}

      not has_admin_access?(account) ->
        socket =
          socket
          |> put_flash(:error, "You don't have permission to access the admin panel.")
          |> redirect(to: "/dashboard")

        {:halt, socket}

      not TOTP.enabled?(account) ->
        # Admin users must have TOTP enabled
        socket =
          socket
          |> put_flash(
            :warning,
            "Two-factor authentication is required for admin access. Please set it up first."
          )
          |> redirect(to: "/settings/totp/setup")

        {:halt, socket}

      true ->
        # Load permissions for sidebar and page-level access checks
        permissions = Authorization.get_account_permissions(account) |> Enum.map(& &1.key)
        socket = assign(socket, :permissions, permissions)
        {:cont, socket}
    end
  end

  defp assign_current_account(socket, session) do
    case session[@session_key] || session["current_account_id"] do
      nil ->
        assign(socket, :current_account, nil)

      account_id ->
        account = Accounts.get_by_id(account_id)
        assign(socket, :current_account, account)
    end
  end

  # Admin permissions that grant access to the admin panel
  @admin_permissions [
    "users.view",
    "users.ban",
    "characters.view",
    "characters.modify_items",
    "economy.view_stats",
    "economy.view_transactions",
    "events.manage",
    "events.broadcast_message",
    "server.view_logs",
    "admin.manage_roles",
    "admin.view_audit_log",
    "testing.manage"
  ]

  defp has_admin_access?(account) do
    Authorization.has_any_permission?(account, @admin_permissions)
  end

  # Server status helpers
  @status_refresh_interval :timer.seconds(30)

  defp assign_server_status(socket) do
    assign(socket, :server_status, fetch_server_status())
  end

  defp maybe_schedule_status_refresh(socket) do
    if connected?(socket) do
      attach_hook(socket, :server_status_refresh, :handle_info, &handle_status_refresh/2)
      |> tap(fn _ ->
        Process.send_after(self(), :refresh_server_status, @status_refresh_interval)
      end)
    else
      socket
    end
  end

  defp handle_status_refresh(:refresh_server_status, socket) do
    Process.send_after(self(), :refresh_server_status, @status_refresh_interval)
    {:halt, assign(socket, :server_status, fetch_server_status())}
  end

  defp handle_status_refresh(_msg, socket), do: {:cont, socket}

  defp fetch_server_status do
    try do
      BezgelorWorld.Portal.server_status()
    rescue
      _ -> %{online_players: 0, maintenance_mode: false, uptime_seconds: 0}
    end
  end

  @doc """
  Check if session has admin access for LiveDashboard.

  Used by LiveDashboard's plug pipeline.
  Returns the conn if admin, halts otherwise.
  """
  def admins_only(conn) do
    account_id = get_session(conn, :current_account_id)

    case account_id && Accounts.get_by_id(account_id) do
      nil ->
        conn
        |> Phoenix.Controller.put_flash(:error, "You must be logged in to access this page.")
        |> Phoenix.Controller.redirect(to: "/login")
        |> Plug.Conn.halt()

      account ->
        if has_admin_access?(account) and TOTP.enabled?(account) do
          conn
        else
          conn
          |> Phoenix.Controller.put_flash(:error, "Admin access with 2FA required.")
          |> Phoenix.Controller.redirect(to: "/dashboard")
          |> Plug.Conn.halt()
        end
    end
  end
end
