defmodule BezgelorPortalWeb.Plugs.RequirePermission do
  @moduledoc """
  Plug that requires the current user to have a specific permission.

  ## Usage

  In your controller:

      plug BezgelorPortalWeb.Plugs.RequirePermission, "users.view" when action in [:index, :show]
      plug BezgelorPortalWeb.Plugs.RequirePermission, "users.ban" when action in [:ban]

  Or check for any of multiple permissions:

      plug BezgelorPortalWeb.Plugs.RequirePermission, ["users.view", "characters.view"]

  ## Behavior

  - Requires `RequireAuth` to have run first (expects `conn.assigns.current_account`)
  - If the user has the permission, continues normally
  - If the user lacks the permission, returns 403 Forbidden

  ## Note

  This plug must be used AFTER `RequireAuth` plug, which sets `current_account`.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias BezgelorDb.Authorization

  def init(permission) when is_binary(permission), do: {:single, permission}
  def init(permissions) when is_list(permissions), do: {:any, permissions}

  def call(conn, {:single, permission}) do
    check_permission(conn, permission, &Authorization.has_permission?/2)
  end

  def call(conn, {:any, permissions}) do
    check_permission(conn, permissions, &Authorization.has_any_permission?/2)
  end

  defp check_permission(conn, permission_or_permissions, check_fn) do
    account = conn.assigns[:current_account]

    cond do
      is_nil(account) ->
        # RequireAuth should have been called first
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Authentication required"})
        |> halt()

      check_fn.(account, permission_or_permissions) ->
        conn

      true ->
        conn
        |> put_status(:forbidden)
        |> put_view(BezgelorPortalWeb.ErrorHTML)
        |> render("403.html")
        |> halt()
    end
  end
end
