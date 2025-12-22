defmodule BezgelorPortalWeb.LoginLive do
  @moduledoc """
  LiveView for user authentication.

  Handles login form submission and displays appropriate error messages
  for invalid credentials, banned accounts, and suspended accounts.

  If TOTP is enabled on the account, redirects to TOTP verification after
  password authentication.
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Accounts
  alias BezgelorPortal.{Auth, TOTP}

  def mount(_params, session, socket) do
    # Check if already logged in AND account still exists
    # Prevents redirect loop when session has stale account_id
    case session["current_account_id"] do
      nil ->
        form = to_form(%{"email" => "", "password" => ""}, as: :login)
        {:ok, assign(socket, form: form, error: nil)}

      account_id ->
        if Accounts.get_by_id(account_id) do
          {:ok, push_navigate(socket, to: ~p"/dashboard")}
        else
          # Account no longer exists - show login form
          # Session will be overwritten on next successful login
          form = to_form(%{"email" => "", "password" => ""}, as: :login)
          {:ok, assign(socket, form: form, error: nil)}
        end
    end
  end

  def render(assigns) do
    ~H"""
    <h2 class="card-title text-2xl justify-center mb-6">Sign In</h2>

    <.form for={@form} phx-submit="login" class="space-y-4">
      <.input
        field={@form[:email]}
        type="email"
        label="Email"
        placeholder="you@example.com"
        required
        autocomplete="email"
      />

      <.input
        field={@form[:password]}
        type="password"
        label="Password"
        placeholder="Enter your password"
        required
        autocomplete="current-password"
      />

      <div :if={@error} class="alert alert-error">
        <.icon name="hero-exclamation-circle" class="size-5" />
        <span>{@error}</span>
      </div>

      <div class="form-control mt-6">
        <.button type="submit" variant="primary" class="w-full">
          Sign In
        </.button>
      </div>
    </.form>

    <div class="divider">OR</div>

    <p class="text-center text-sm text-base-content/70">
      Don't have an account? <.link href="/register" class="link link-primary">Create one</.link>
    </p>
    """
  end

  def handle_event("login", %{"login" => %{"email" => email, "password" => password}}, socket) do
    case Auth.authenticate(email, password) do
      {:ok, account} ->
        # Check if TOTP is enabled
        if TOTP.enabled?(account) do
          # Redirect to TOTP verification page
          # We pass a token that will be verified on the other side
          {:noreply,
           socket
           |> push_navigate(
             to: ~p"/auth/totp-verify?pending=#{generate_totp_pending_token(account)}"
           )}
        else
          # No TOTP - proceed directly to login
          {:noreply,
           socket
           |> push_navigate(
             to: ~p"/auth/callback?email=#{email}&token=#{generate_login_token(account)}"
           )}
        end

      {:error, :invalid_credentials} ->
        {:noreply, assign(socket, error: "Invalid email or password.")}

      {:error, :account_banned} ->
        {:noreply, assign(socket, error: "This account has been permanently banned.")}

      {:error, {:account_suspended, days}} ->
        days_text = if days < 1, do: "less than a day", else: "#{Float.round(days, 1)} days"

        {:noreply,
         assign(socket, error: "This account is suspended. Time remaining: #{days_text}.")}
    end
  end

  # Generate a short-lived token for the callback
  # This is a simple approach - in production you might want a more robust solution
  defp generate_login_token(account) do
    Phoenix.Token.sign(BezgelorPortalWeb.Endpoint, "login_token", account.id)
  end

  # Generate a token for TOTP pending verification (short-lived, 5 minutes)
  defp generate_totp_pending_token(account) do
    Phoenix.Token.sign(
      BezgelorPortalWeb.Endpoint,
      "totp_pending",
      {account.id, System.system_time(:second)}
    )
  end
end
