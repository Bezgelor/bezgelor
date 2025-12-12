defmodule BezgelorPortalWeb.EmailChangeController do
  @moduledoc """
  Controller for email change verification.

  Handles the verification link clicked from the email change confirmation email.
  """
  use BezgelorPortalWeb, :controller

  alias BezgelorDb.Accounts
  alias BezgelorPortal.Notifier

  @doc """
  Verify an email change token and update the account's email.

  GET /verify-email-change/:token
  """
  def verify(conn, %{"token" => token}) do
    case Notifier.verify_email_change_token(token) do
      {:ok, {account_id, new_email}} ->
        case Accounts.get_by_id(account_id) do
          nil ->
            conn
            |> put_flash(:error, "Account not found.")
            |> redirect(to: ~p"/settings")

          account ->
            # Check if the new email is already taken
            if Accounts.email_exists?(new_email) and String.downcase(new_email) != String.downcase(account.email) do
              conn
              |> put_flash(:error, "This email address is already in use by another account.")
              |> redirect(to: ~p"/settings")
            else
              case Accounts.update_email(account, new_email) do
                {:ok, _updated_account} ->
                  conn
                  |> put_flash(:info, "Email address updated successfully! You may need to log in again.")
                  |> redirect(to: ~p"/logout")

                {:error, _changeset} ->
                  conn
                  |> put_flash(:error, "Failed to update email address. Please try again.")
                  |> redirect(to: ~p"/settings")
              end
            end
        end

      {:error, :token_expired} ->
        conn
        |> put_flash(:error, "This verification link has expired. Please request a new email change.")
        |> redirect(to: ~p"/settings")

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "Invalid verification link.")
        |> redirect(to: ~p"/settings")
    end
  end
end
