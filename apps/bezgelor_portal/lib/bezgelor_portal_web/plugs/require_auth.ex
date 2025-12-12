defmodule BezgelorPortalWeb.Plugs.RequireAuth do
  @moduledoc """
  Plug that requires a user to be authenticated.

  ## Usage

  In your router:

      pipeline :authenticated do
        plug BezgelorPortalWeb.Plugs.RequireAuth
      end

  Or in a controller:

      plug BezgelorPortalWeb.Plugs.RequireAuth

  ## Behavior

  - If the user is authenticated, loads the account into `conn.assigns.current_account`
  - If the user is not authenticated, redirects to the login page with a flash message
  """

  import Plug.Conn
  import Phoenix.Controller

  alias BezgelorPortal.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    case Auth.get_current_account(conn) do
      nil ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/login")
        |> halt()

      account ->
        assign(conn, :current_account, account)
    end
  end
end
