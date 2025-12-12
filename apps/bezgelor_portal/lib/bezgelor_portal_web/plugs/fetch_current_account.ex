defmodule BezgelorPortalWeb.Plugs.FetchCurrentAccount do
  @moduledoc """
  Plug that fetches the current account from the session.

  This plug should be added to the browser pipeline to make the
  current account available in all requests (if logged in).

  ## Usage

  In your router:

      pipeline :browser do
        ...
        plug BezgelorPortalWeb.Plugs.FetchCurrentAccount
      end

  ## Behavior

  - Fetches the account from session if present
  - Sets `conn.assigns.current_account` (nil if not logged in)
  - Does NOT redirect - use `RequireAuth` for that
  """

  import Plug.Conn

  alias BezgelorPortal.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    account = Auth.get_current_account(conn)
    assign(conn, :current_account, account)
  end
end
