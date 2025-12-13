defmodule BezgelorPortalWeb.ContentController do
  use BezgelorPortalWeb, :controller

  def about(conn, _params) do
    render(conn, :about, current_account: conn.assigns[:current_account])
  end

  def terms(conn, _params) do
    render(conn, :terms, current_account: conn.assigns[:current_account])
  end

  def privacy(conn, _params) do
    render(conn, :privacy, current_account: conn.assigns[:current_account])
  end

  def download(conn, _params) do
    render(conn, :download, current_account: conn.assigns[:current_account])
  end

  def community(conn, _params) do
    render(conn, :community, current_account: conn.assigns[:current_account])
  end

  def news(conn, _params) do
    render(conn, :news, current_account: conn.assigns[:current_account])
  end
end
