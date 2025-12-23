defmodule BezgelorPortal.Notifier do
  @moduledoc """
  Email notifications for the Account Portal.

  Handles sending verification emails, password resets, and other
  account-related notifications.

  ## Usage

      Notifier.deliver_verification_email(account)
      Notifier.deliver_password_reset_email(account)
  """

  import Swoosh.Email
  require Logger

  alias BezgelorPortal.Mailer
  alias BezgelorDb.Schema.Account

  # Token validity: 24 hours for verification, 1 hour for password reset
  @verification_token_max_age 86_400
  @password_reset_token_max_age 3_600

  @from_email {"Bezgelor", "noreply@bezgelor.com"}

  @doc """
  Send email verification link to a newly registered account.
  """
  @spec deliver_verification_email(Account.t()) :: {:ok, Swoosh.Email.t()} | {:error, any()}
  def deliver_verification_email(account) do
    token = generate_verification_token(account)
    verification_url = url("/verify/#{token}")

    email =
      new()
      |> to(account.email)
      |> from(@from_email)
      |> subject("Verify your Bezgelor account")
      |> html_body(verification_email_html(account, verification_url))
      |> text_body(verification_email_text(account, verification_url))

    deliver_with_logging(email, :verification, account.email)
  end

  @doc """
  Send password reset link to an account.
  """
  @spec deliver_password_reset_email(Account.t()) :: {:ok, Swoosh.Email.t()} | {:error, any()}
  def deliver_password_reset_email(account) do
    token = generate_password_reset_token(account)
    reset_url = url("/reset-password/#{token}")

    email =
      new()
      |> to(account.email)
      |> from(@from_email)
      |> subject("Reset your Bezgelor password")
      |> html_body(password_reset_email_html(account, reset_url))
      |> text_body(password_reset_email_text(account, reset_url))

    deliver_with_logging(email, :password_reset, account.email)
  end

  @doc """
  Verify an email verification token.

  Returns `{:ok, account_id}` if valid, `{:error, reason}` otherwise.
  """
  @spec verify_email_token(String.t()) :: {:ok, integer()} | {:error, atom()}
  def verify_email_token(token) do
    case Phoenix.Token.verify(
           BezgelorPortalWeb.Endpoint,
           "email_verification",
           token,
           max_age: @verification_token_max_age
         ) do
      {:ok, account_id} -> {:ok, account_id}
      {:error, :expired} -> {:error, :token_expired}
      {:error, :invalid} -> {:error, :invalid_token}
    end
  end

  @doc """
  Verify a password reset token.

  Returns `{:ok, account_id}` if valid, `{:error, reason}` otherwise.
  """
  @spec verify_password_reset_token(String.t()) :: {:ok, integer()} | {:error, atom()}
  def verify_password_reset_token(token) do
    case Phoenix.Token.verify(
           BezgelorPortalWeb.Endpoint,
           "password_reset",
           token,
           max_age: @password_reset_token_max_age
         ) do
      {:ok, account_id} -> {:ok, account_id}
      {:error, :expired} -> {:error, :token_expired}
      {:error, :invalid} -> {:error, :invalid_token}
    end
  end

  @doc """
  Send email change verification to a new email address.

  The token encodes both the account ID and the new email address.
  """
  @spec deliver_email_change_verification(Account.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, any()}
  def deliver_email_change_verification(account, new_email) do
    token = generate_email_change_token(account, new_email)
    verification_url = url("/verify-email-change/#{token}")

    email =
      new()
      |> to(new_email)
      |> from(@from_email)
      |> subject("Verify your new email address")
      |> html_body(email_change_html(new_email, verification_url))
      |> text_body(email_change_text(new_email, verification_url))

    deliver_with_logging(email, :email_change, new_email)
  end

  @doc """
  Verify an email change token.

  Returns `{:ok, {account_id, new_email}}` if valid, `{:error, reason}` otherwise.
  """
  @spec verify_email_change_token(String.t()) :: {:ok, {integer(), String.t()}} | {:error, atom()}
  def verify_email_change_token(token) do
    case Phoenix.Token.verify(
           BezgelorPortalWeb.Endpoint,
           "email_change",
           token,
           max_age: @verification_token_max_age
         ) do
      {:ok, {account_id, new_email}} -> {:ok, {account_id, new_email}}
      {:error, :expired} -> {:error, :token_expired}
      {:error, :invalid} -> {:error, :invalid_token}
    end
  end

  # Generate a signed token for email verification
  defp generate_verification_token(account) do
    Phoenix.Token.sign(BezgelorPortalWeb.Endpoint, "email_verification", account.id)
  end

  # Generate a signed token for email change (encodes account_id and new_email)
  defp generate_email_change_token(account, new_email) do
    Phoenix.Token.sign(BezgelorPortalWeb.Endpoint, "email_change", {account.id, new_email})
  end

  # Generate a signed token for password reset
  defp generate_password_reset_token(account) do
    Phoenix.Token.sign(BezgelorPortalWeb.Endpoint, "password_reset", account.id)
  end

  # Generate URL helper
  defp url(path) do
    BezgelorPortalWeb.Endpoint.url() <> path
  end

  # Deliver email with logging
  defp deliver_with_logging(email, type, recipient) do
    case Mailer.deliver(email) do
      {:ok, _metadata} = result ->
        Logger.info("[Email] Sent #{type} email to #{recipient}")
        result

      {:error, reason} = result ->
        Logger.error("[Email] Failed to send #{type} email to #{recipient}: #{inspect(reason)}")
        result
    end
  end

  # Email templates

  defp verification_email_html(_account, url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { text-align: center; padding: 20px 0; }
        .header h1 { color: #6366f1; margin: 0; }
        .content { background: #f9fafb; border-radius: 8px; padding: 30px; margin: 20px 0; }
        .button { display: inline-block; background: #6366f1; color: white; padding: 12px 30px; text-decoration: none; border-radius: 6px; font-weight: 500; }
        .button:hover { background: #4f46e5; }
        .footer { text-align: center; color: #6b7280; font-size: 14px; padding: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Bezgelor</h1>
        </div>
        <div class="content">
          <h2>Welcome to Bezgelor!</h2>
          <p>Thank you for creating an account. Please verify your email address by clicking the button below:</p>
          <p style="text-align: center; margin: 30px 0;">
            <a href="#{url}" class="button">Verify Email Address</a>
          </p>
          <p>Or copy and paste this link into your browser:</p>
          <p style="word-break: break-all; color: #6366f1;">#{url}</p>
          <p><strong>This link will expire in 24 hours.</strong></p>
        </div>
        <div class="footer">
          <p>If you didn't create an account, you can safely ignore this email.</p>
          <p>Bezgelor WildStar Server Emulator</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp verification_email_text(_account, url) do
    """
    Welcome to Bezgelor!

    Thank you for creating an account. Please verify your email address by visiting the link below:

    #{url}

    This link will expire in 24 hours.

    If you didn't create an account, you can safely ignore this email.

    --
    Bezgelor WildStar Server Emulator
    """
  end

  defp password_reset_email_html(_account, url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { text-align: center; padding: 20px 0; }
        .header h1 { color: #6366f1; margin: 0; }
        .content { background: #f9fafb; border-radius: 8px; padding: 30px; margin: 20px 0; }
        .button { display: inline-block; background: #6366f1; color: white; padding: 12px 30px; text-decoration: none; border-radius: 6px; font-weight: 500; }
        .footer { text-align: center; color: #6b7280; font-size: 14px; padding: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Bezgelor</h1>
        </div>
        <div class="content">
          <h2>Password Reset Request</h2>
          <p>We received a request to reset your password. Click the button below to choose a new password:</p>
          <p style="text-align: center; margin: 30px 0;">
            <a href="#{url}" class="button">Reset Password</a>
          </p>
          <p>Or copy and paste this link into your browser:</p>
          <p style="word-break: break-all; color: #6366f1;">#{url}</p>
          <p><strong>This link will expire in 1 hour.</strong></p>
        </div>
        <div class="footer">
          <p>If you didn't request a password reset, you can safely ignore this email.</p>
          <p>Bezgelor WildStar Server Emulator</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp password_reset_email_text(_account, url) do
    """
    Password Reset Request

    We received a request to reset your password. Visit the link below to choose a new password:

    #{url}

    This link will expire in 1 hour.

    If you didn't request a password reset, you can safely ignore this email.

    --
    Bezgelor WildStar Server Emulator
    """
  end

  defp email_change_html(new_email, url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { text-align: center; padding: 20px 0; }
        .header h1 { color: #6366f1; margin: 0; }
        .content { background: #f9fafb; border-radius: 8px; padding: 30px; margin: 20px 0; }
        .button { display: inline-block; background: #6366f1; color: white; padding: 12px 30px; text-decoration: none; border-radius: 6px; font-weight: 500; }
        .footer { text-align: center; color: #6b7280; font-size: 14px; padding: 20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Bezgelor</h1>
        </div>
        <div class="content">
          <h2>Verify Your New Email Address</h2>
          <p>You've requested to change your email address to <strong>#{new_email}</strong>.</p>
          <p>Click the button below to verify this email address:</p>
          <p style="text-align: center; margin: 30px 0;">
            <a href="#{url}" class="button">Verify New Email</a>
          </p>
          <p>Or copy and paste this link into your browser:</p>
          <p style="word-break: break-all; color: #6366f1;">#{url}</p>
          <p><strong>This link will expire in 24 hours.</strong></p>
        </div>
        <div class="footer">
          <p>If you didn't request this change, you can safely ignore this email.</p>
          <p>Bezgelor WildStar Server Emulator</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp email_change_text(new_email, url) do
    """
    Verify Your New Email Address

    You've requested to change your email address to #{new_email}.

    Please verify this email address by visiting the link below:

    #{url}

    This link will expire in 24 hours.

    If you didn't request this change, you can safely ignore this email.

    --
    Bezgelor WildStar Server Emulator
    """
  end
end
