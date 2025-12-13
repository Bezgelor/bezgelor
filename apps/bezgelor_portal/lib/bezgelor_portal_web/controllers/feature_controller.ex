defmodule BezgelorPortalWeb.FeatureController do
  use BezgelorPortalWeb, :controller

  @doc """
  Renders the features overview page.
  """
  def index(conn, _params) do
    render(conn, :index, current_account: conn.assigns[:current_account])
  end

  @doc """
  Renders the races feature page.
  """
  def races(conn, _params) do
    render(conn, :races, current_account: conn.assigns[:current_account])
  end

  @doc """
  Renders the classes feature page.
  """
  def classes(conn, _params) do
    render(conn, :classes, current_account: conn.assigns[:current_account])
  end

  @doc """
  Renders the combat feature page.
  """
  def combat(conn, _params) do
    render(conn, :combat, current_account: conn.assigns[:current_account])
  end

  @doc """
  Renders the housing feature page.
  """
  def housing(conn, _params) do
    render(conn, :housing, current_account: conn.assigns[:current_account])
  end

  @doc """
  Renders the paths feature page.
  """
  def paths(conn, _params) do
    render(conn, :paths, current_account: conn.assigns[:current_account])
  end

  @doc """
  Renders the dungeons feature page.
  """
  def dungeons(conn, _params) do
    render(conn, :dungeons, current_account: conn.assigns[:current_account])
  end
end
