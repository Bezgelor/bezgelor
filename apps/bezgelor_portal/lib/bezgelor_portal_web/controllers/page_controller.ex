defmodule BezgelorPortalWeb.PageController do
  use BezgelorPortalWeb, :controller

  @doc """
  Redirect to dashboard if logged in, otherwise to login.
  """
  def home(conn, _params) do
    if conn.assigns[:current_account] do
      redirect(conn, to: ~p"/dashboard")
    else
      redirect(conn, to: ~p"/login")
    end
  end
end
