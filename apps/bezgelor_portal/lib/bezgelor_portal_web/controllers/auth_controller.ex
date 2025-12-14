defmodule BezgelorPortalWeb.AuthController do
  @moduledoc """
  Controller for authentication actions that require session manipulation.

  LiveView cannot directly modify Plug sessions, so we use this controller
  for login callbacks and logout.
  """
  use BezgelorPortalWeb, :controller

  alias BezgelorPortal.Auth
  alias BezgelorDb.Accounts

  @doc """
  Handle login callback from LiveView.

  Validates the login token, sets the session, and redirects to dashboard.
  """
  def callback(conn, %{"email" => email, "token" => token}) do
    # Verify the token (valid for 60 seconds)
    case Phoenix.Token.verify(BezgelorPortalWeb.Endpoint, "login_token", token, max_age: 60) do
      {:ok, account_id} ->
        # Double-check the account exists and matches the email
        case Accounts.get_by_id(account_id) do
          %{email: ^email} = account ->
            conn
            |> Auth.login(account)
            |> put_flash(:info, "Welcome back!")
            |> redirect(to: ~p"/dashboard")

          _ ->
            conn
            |> put_flash(:error, "Invalid login attempt.")
            |> redirect(to: ~p"/login")
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Login session expired. Please try again.")
        |> redirect(to: ~p"/login")
    end
  end

  # Handle login callback after TOTP verification - this is called after the user successfully enters their TOTP code
  def callback(conn, %{"totp_verified" => account_id_str, "token" => token}) do
    # Verify the TOTP verified token (valid for 60 seconds)
    case Phoenix.Token.verify(BezgelorPortalWeb.Endpoint, "totp_verified_login", token, max_age: 60) do
      {:ok, verified_account_id} ->
        # Ensure the account IDs match
        {account_id, _} = Integer.parse(account_id_str)

        if account_id == verified_account_id do
          case Accounts.get_by_id(account_id) do
            nil ->
              conn
              |> put_flash(:error, "Account not found.")
              |> redirect(to: ~p"/login")

            account ->
              conn
              |> Auth.login(account)
              |> put_flash(:info, "Welcome back!")
              |> redirect(to: ~p"/dashboard")
          end
        else
          conn
          |> put_flash(:error, "Invalid login attempt.")
          |> redirect(to: ~p"/login")
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Login session expired. Please try again.")
        |> redirect(to: ~p"/login")
    end
  end

  @doc """
  Log out the current user.
  """
  def logout(conn, _params) do
    conn
    |> Auth.logout()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end
end
