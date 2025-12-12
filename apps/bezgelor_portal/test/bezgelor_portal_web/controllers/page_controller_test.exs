defmodule BezgelorPortalWeb.PageControllerTest do
  use BezgelorPortalWeb.ConnCase

  test "GET / redirects to login when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/login"
  end
end
