defmodule BezgelorPortalWeb.VerificationController do
  @moduledoc """
  Controller for email verification.

  Handles the verification link clicked from the email.
  """
  use BezgelorPortalWeb, :controller

  alias BezgelorDb.Accounts
  alias BezgelorPortal.Notifier

  @doc """
  Verify an email verification token.

  GET /verify/:token
  """
  def verify(conn, %{"token" => token}) do
    case Notifier.verify_email_token(token) do
      {:ok, account_id} ->
        case Accounts.get_by_id(account_id) do
          nil ->
            conn
            |> put_flash(:error, "Account not found.")
            |> redirect(to: ~p"/login")

          account ->
            if Accounts.email_verified?(account) do
              conn
              |> put_flash(:info, "Your email has already been verified. You can log in.")
              |> redirect(to: ~p"/login")
            else
              case Accounts.verify_email(account) do
                {:ok, _account} ->
                  conn
                  |> put_flash(:info, "Email verified successfully! You can now log in.")
                  |> redirect(to: ~p"/login")

                {:error, _changeset} ->
                  conn
                  |> put_flash(:error, "Failed to verify email. Please try again.")
                  |> redirect(to: ~p"/login")
              end
            end
        end

      {:error, :token_expired} ->
        conn
        |> put_flash(:error, "This verification link has expired. Please request a new one.")
        |> redirect(to: ~p"/login")

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "Invalid verification link.")
        |> redirect(to: ~p"/login")
    end
  end
end
