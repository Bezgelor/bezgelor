defmodule BezgelorPortalWeb.TotpDisableLive do
  @moduledoc """
  LiveView for disabling TOTP (Two-Factor Authentication).

  Requires current password and TOTP code to disable.
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorPortal.TOTP
  alias BezgelorCrypto.Password

  def mount(_params, _session, socket) do
    account = socket.assigns.current_account

    # Redirect if TOTP is not enabled
    if not TOTP.enabled?(account) do
      {:ok,
       socket
       |> put_flash(:info, "Two-factor authentication is not enabled.")
       |> push_navigate(to: ~p"/settings")}
    else
      {:ok,
       assign(socket,
         page_title: "Disable Two-Factor Authentication",
         form: to_form(%{"password" => "", "code" => ""}, as: :disable),
         error: nil
       )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto max-w-lg px-4 py-8">
      <nav class="breadcrumbs text-sm mb-4">
        <ul>
          <li><.link navigate={~p"/dashboard"}>Dashboard</.link></li>
          <li><.link navigate={~p"/settings"}>Settings</.link></li>
          <li>Disable Two-Factor</li>
        </ul>
      </nav>

      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-2xl mb-2">Disable Two-Factor Authentication</h2>

          <div class="alert alert-warning mb-6">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span>This will make your account less secure.</span>
          </div>

          <p class="text-base-content/70 mb-6">
            To disable two-factor authentication, please enter your current password
            and a code from your authenticator app.
          </p>

          <.form for={@form} phx-submit="disable" class="space-y-4">
            <.input
              field={@form[:password]}
              type="password"
              label="Current Password"
              placeholder="Enter your password"
              required
              autocomplete="current-password"
            />

            <.input
              field={@form[:code]}
              type="text"
              inputmode="numeric"
              pattern="[0-9]*"
              maxlength="6"
              label="Authenticator Code"
              placeholder="000000"
              required
              autocomplete="one-time-code"
              class="font-mono tracking-widest"
            />

            <div :if={@error} class="alert alert-error">
              <.icon name="hero-exclamation-circle" class="size-5" />
              <span>{@error}</span>
            </div>

            <div class="flex gap-3 mt-6">
              <.link href={~p"/settings"} class="btn btn-ghost">
                Cancel
              </.link>
              <button type="submit" class="btn btn-error flex-1">
                <.icon name="hero-shield-exclamation" class="size-4 mr-2" /> Disable 2FA
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("disable", %{"disable" => %{"password" => password, "code" => code}}, socket) do
    account = socket.assigns.current_account

    # Verify password first
    if Password.verify_password(account.email, password, account.salt, account.verifier) do
      # Verify TOTP code
      case TOTP.verify_login_code(account, code) do
        {:ok, _type} ->
          # Disable TOTP
          case TOTP.disable_totp(account) do
            {:ok, _updated_account} ->
              {:noreply,
               socket
               |> put_flash(:info, "Two-factor authentication has been disabled.")
               |> push_navigate(to: ~p"/settings")}

            {:error, _changeset} ->
              {:noreply, assign(socket, error: "Failed to disable two-factor authentication.")}
          end

        {:error, :invalid_code} ->
          {:noreply, assign(socket, error: "Invalid authenticator code.")}

        {:error, :totp_not_enabled} ->
          {:noreply, push_navigate(socket, to: ~p"/settings")}
      end
    else
      {:noreply, assign(socket, error: "Invalid password.")}
    end
  end
end
