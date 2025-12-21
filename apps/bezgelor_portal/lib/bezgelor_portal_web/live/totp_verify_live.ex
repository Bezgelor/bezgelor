defmodule BezgelorPortalWeb.TotpVerifyLive do
  @moduledoc """
  LiveView for TOTP verification during login.

  Shown after successful password verification when the account has TOTP enabled.
  Accepts either a TOTP code or backup code.
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Accounts
  alias BezgelorPortal.TOTP

  # 5 minutes to enter TOTP code
  @session_timeout_seconds 300

  def mount(params, _session, socket) do
    # Get the pending token from params
    pending_token = params["pending"]

    case verify_pending_token(pending_token) do
      {:ok, {account_id, timestamp}} ->
        if session_expired?(timestamp) do
          {:ok,
           socket
           |> put_flash(:error, "Session expired. Please log in again.")
           |> push_navigate(to: ~p"/login")}
        else
          account = Accounts.get_by_id(account_id)

          if account && TOTP.enabled?(account) do
            remaining_codes = TOTP.remaining_backup_codes(account)

            {:ok,
             assign(socket,
               page_title: "Two-Factor Authentication",
               account_id: account_id,
               form: to_form(%{"code" => ""}, as: :totp),
               error: nil,
               show_backup: false,
               remaining_backup_codes: remaining_codes
             )}
          else
            {:ok,
             socket
             |> put_flash(:error, "Invalid session. Please log in again.")
             |> push_navigate(to: ~p"/login")}
          end
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Session expired. Please log in again.")
         |> push_navigate(to: ~p"/login")}
    end
  end

  defp verify_pending_token(nil), do: {:error, :missing_token}

  defp verify_pending_token(token) do
    case Phoenix.Token.verify(BezgelorPortalWeb.Endpoint, "totp_pending", token,
           max_age: @session_timeout_seconds
         ) do
      {:ok, {account_id, timestamp}} -> {:ok, {account_id, timestamp}}
      {:error, reason} -> {:error, reason}
    end
  end

  def render(assigns) do
    ~H"""
    <h2 class="card-title text-2xl justify-center mb-6">Two-Factor Authentication</h2>

    <p class="text-center text-base-content/70 mb-6">
      Enter the 6-digit code from your authenticator app.
    </p>

    <.form for={@form} phx-submit="verify" class="space-y-4">
      <.input
        field={@form[:code]}
        type="text"
        inputmode="numeric"
        pattern={if @show_backup, do: "[A-Za-z0-9\\-]*", else: "[0-9]*"}
        maxlength={if @show_backup, do: "9", else: "6"}
        placeholder={if @show_backup, do: "XXXX-XXXX", else: "000000"}
        autocomplete="one-time-code"
        class="text-center text-2xl tracking-widest font-mono"
        autofocus
      />

      <div :if={@error} class="alert alert-error">
        <.icon name="hero-exclamation-circle" class="size-5" />
        <span>{@error}</span>
      </div>

      <div class="form-control mt-6">
        <.button type="submit" variant="primary" class="w-full">
          Verify
        </.button>
      </div>
    </.form>

    <div class="divider">OR</div>

    <div class="text-center">
      <%= if @show_backup do %>
        <button type="button" class="link link-primary text-sm" phx-click="toggle_backup">
          Use authenticator code instead
        </button>
      <% else %>
        <button type="button" class="link link-primary text-sm" phx-click="toggle_backup">
          Use a backup code
        </button>
        <p :if={@remaining_backup_codes > 0} class="text-xs text-base-content/50 mt-1">
          {if @remaining_backup_codes == 1,
            do: "1 backup code remaining",
            else: "#{@remaining_backup_codes} backup codes remaining"}
        </p>
      <% end %>
    </div>

    <p class="text-center text-sm text-base-content/70 mt-6">
      <.link href={~p"/login"} class="link link-primary">
        <.icon name="hero-arrow-left" class="size-3 inline" /> Back to login
      </.link>
    </p>
    """
  end

  def handle_event("toggle_backup", _params, socket) do
    {:noreply,
     socket
     |> assign(show_backup: !socket.assigns.show_backup)
     |> assign(form: to_form(%{"code" => ""}, as: :totp), error: nil)}
  end

  def handle_event("verify", %{"totp" => %{"code" => code}}, socket) do
    account_id = socket.assigns.account_id
    account = Accounts.get_by_id(account_id)

    if account do
      case TOTP.verify_login_code(account, code) do
        {:ok, _type} ->
          # Verification successful - redirect to auth callback to complete login
          {:noreply,
           socket
           |> push_navigate(
             to:
               ~p"/auth/callback?totp_verified=#{account_id}&token=#{generate_login_token(account)}"
           )}

        {:error, :invalid_code} ->
          {:noreply, assign(socket, error: "Invalid code. Please try again.")}

        {:error, :totp_not_enabled} ->
          {:noreply,
           socket
           |> put_flash(:error, "TOTP is not enabled on this account.")
           |> push_navigate(to: ~p"/login")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Account not found.")
       |> push_navigate(to: ~p"/login")}
    end
  end

  defp session_expired?(nil), do: true

  defp session_expired?(timestamp) when is_integer(timestamp) do
    now = System.system_time(:second)
    now - timestamp > @session_timeout_seconds
  end

  defp session_expired?(_), do: true

  defp generate_login_token(account) do
    Phoenix.Token.sign(BezgelorPortalWeb.Endpoint, "totp_verified_login", account.id)
  end
end
