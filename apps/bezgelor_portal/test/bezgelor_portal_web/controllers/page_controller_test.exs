defmodule BezgelorPortalWeb.PageControllerTest do
  use BezgelorPortalWeb.ConnCase

  test "GET / renders the home page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Bezgelor"
  end
end
