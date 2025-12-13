defmodule BezgelorPortalWeb.PageController do
  use BezgelorPortalWeb, :controller

  @doc """
  Renders the gaming homepage.
  """
  def home(conn, _params) do
    render(conn, :home, current_account: conn.assigns[:current_account])
  end
end
