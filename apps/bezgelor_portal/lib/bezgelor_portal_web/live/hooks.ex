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
          |> put_flash(:warning, "Two-factor authentication is required for admin access. Please set it up first.")
          |> redirect(to: "/settings/totp/setup")

        {:halt, socket}

      true ->
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

  defp has_admin_access?(account) do
    permissions = Authorization.get_account_permissions(account)
    length(permissions) > 0
  end
end
