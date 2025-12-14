defmodule BezgelorPortalWeb.TotpSetupLive do
  @moduledoc """
  LiveView for TOTP (Two-Factor Authentication) setup.

  Guides users through enabling two-factor authentication:
  1. Scan QR code or enter secret manually
  2. Verify with a code from authenticator app
  3. View and save backup codes
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorPortal.TOTP

  def mount(_params, _session, socket) do
    account = socket.assigns.current_account

    # Redirect if TOTP is already enabled
    if TOTP.enabled?(account) do
      {:ok,
       socket
       |> put_flash(:info, "Two-factor authentication is already enabled.")
       |> push_navigate(to: ~p"/settings")}
    else
      # Generate setup info
      {:ok, setup} = TOTP.generate_setup(account.email)

      # Generate backup codes
      {plaintext_codes, hashed_codes} = TOTP.generate_backup_codes()

      {:ok,
       assign(socket,
         page_title: "Enable Two-Factor Authentication",
         step: :setup,
         setup: setup,
         backup_codes: plaintext_codes,
         hashed_codes: hashed_codes,
         code_form: to_form(%{"code" => ""}, as: :verify),
         error: nil,
         show_secret: false
       )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto max-w-2xl px-4 py-8">
      <nav class="breadcrumbs text-sm mb-4">
        <ul>
          <li><.link navigate={~p"/dashboard"}>Dashboard</.link></li>
          <li><.link navigate={~p"/settings"}>Settings</.link></li>
          <li>Two-Factor Setup</li>
        </ul>
      </nav>

      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <%= case @step do %>
            <% :setup -> %>
              <.setup_step
                setup={@setup}
                show_secret={@show_secret}
                form={@code_form}
                error={@error}
              />
            <% :backup_codes -> %>
              <.backup_codes_step backup_codes={@backup_codes} />
            <% :complete -> %>
              <.complete_step />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Setup Step - QR code and verification
  attr :setup, :map, required: true
  attr :show_secret, :boolean, required: true
  attr :form, :map, required: true
  attr :error, :string, default: nil

  defp setup_step(assigns) do
    ~H"""
    <div>
      <h2 class="card-title text-2xl mb-2">Enable Two-Factor Authentication</h2>
      <p class="text-base-content/70 mb-6">
        Scan the QR code with your authenticator app (Google Authenticator, Authy, etc.)
      </p>

      <div class="flex flex-col lg:flex-row gap-8">
        <div class="flex-1">
          <div class="bg-white p-4 rounded-lg inline-block">
            {raw(@setup.qr_code_svg)}
          </div>

          <div class="mt-4">
            <button
              type="button"
              class="btn btn-sm btn-ghost"
              phx-click="toggle_secret"
            >
              <.icon name="hero-key" class="size-4 mr-1" />
              {if @show_secret, do: "Hide", else: "Can't scan? Show secret key"}
            </button>

            <div :if={@show_secret} class="mt-2 p-3 bg-base-200 rounded-lg">
              <p class="text-xs text-base-content/60 mb-1">Manual entry key:</p>
              <code class="text-sm font-mono select-all">{@setup.secret_base32}</code>
            </div>
          </div>
        </div>

        <div class="flex-1">
          <h3 class="font-semibold mb-4">Verify Setup</h3>
          <p class="text-sm text-base-content/70 mb-4">
            Enter the 6-digit code from your authenticator app to verify:
          </p>

          <.form for={@form} phx-submit="verify_code" class="space-y-4">
            <.input
              field={@form[:code]}
              type="text"
              inputmode="numeric"
              pattern="[0-9]*"
              maxlength="6"
              placeholder="000000"
              autocomplete="one-time-code"
              class="text-center text-2xl tracking-widest font-mono"
            />

            <div :if={@error} class="alert alert-error">
              <.icon name="hero-exclamation-circle" class="size-5" />
              <span>{@error}</span>
            </div>

            <div class="flex gap-3">
              <.link href={~p"/settings"} class="btn btn-ghost">
                Cancel
              </.link>
              <.button type="submit" variant="primary" class="flex-1">
                Verify & Enable
              </.button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  # Backup Codes Step - Display codes to save
  attr :backup_codes, :list, required: true

  defp backup_codes_step(assigns) do
    ~H"""
    <div>
      <h2 class="card-title text-2xl mb-2">
        <.icon name="hero-check-circle" class="size-8 text-success" />
        Two-Factor Authentication Enabled
      </h2>

      <div class="alert alert-warning my-6">
        <.icon name="hero-exclamation-triangle" class="size-6" />
        <div>
          <h3 class="font-bold">Save Your Backup Codes</h3>
          <p class="text-sm">
            If you lose access to your authenticator app, you can use these codes to log in.
            Each code can only be used once. Store them somewhere safe!
          </p>
        </div>
      </div>

      <div class="bg-base-200 rounded-lg p-6 mb-6">
        <div class="grid grid-cols-2 gap-3">
          <%= for code <- @backup_codes do %>
            <code class="bg-base-100 p-2 rounded text-center font-mono select-all">
              {code}
            </code>
          <% end %>
        </div>
      </div>

      <div class="flex gap-3">
        <button type="button" class="btn btn-outline" phx-click="copy_codes">
          <.icon name="hero-clipboard-document" class="size-4 mr-2" />
          Copy Codes
        </button>
        <button type="button" class="btn btn-outline" phx-click="download_codes">
          <.icon name="hero-arrow-down-tray" class="size-4 mr-2" />
          Download
        </button>
        <div class="flex-1"></div>
        <.link href={~p"/settings"} class="btn btn-primary">
          I've Saved My Codes
        </.link>
      </div>
    </div>
    """
  end

  # Complete Step (fallback)
  defp complete_step(assigns) do
    ~H"""
    <div class="text-center py-8">
      <.icon name="hero-check-circle" class="size-16 text-success mx-auto mb-4" />
      <h2 class="text-2xl font-bold mb-2">All Set!</h2>
      <p class="text-base-content/70 mb-6">
        Two-factor authentication is now enabled on your account.
      </p>
      <.link href={~p"/settings"} class="btn btn-primary">
        Return to Settings
      </.link>
    </div>
    """
  end

  # Event Handlers

  def handle_event("toggle_secret", _params, socket) do
    {:noreply, assign(socket, show_secret: !socket.assigns.show_secret)}
  end

  def handle_event("verify_code", %{"verify" => %{"code" => code}}, socket) do
    setup = socket.assigns.setup

    case TOTP.validate_code(setup.secret, code) do
      :ok ->
        # Enable TOTP on the account
        account = socket.assigns.current_account
        hashed_codes = socket.assigns.hashed_codes

        case TOTP.enable_totp(account, setup.secret, hashed_codes) do
          {:ok, _updated_account} ->
            {:noreply, assign(socket, step: :backup_codes)}

          {:error, _changeset} ->
            {:noreply, assign(socket, error: "Failed to enable two-factor authentication. Please try again.")}
        end

      {:error, :invalid_code} ->
        {:noreply, assign(socket, error: "Invalid code. Please try again.")}
    end
  end

  def handle_event("copy_codes", _params, socket) do
    codes = socket.assigns.backup_codes |> Enum.join("\n")

    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: codes})
     |> put_flash(:info, "Backup codes copied to clipboard")}
  end

  def handle_event("download_codes", _params, socket) do
    codes = socket.assigns.backup_codes

    content = """
    Bezgelor Backup Codes
    =====================
    Generated: #{DateTime.utc_now() |> DateTime.to_string()}

    IMPORTANT: Each code can only be used once.
    Keep these codes in a safe place.

    #{Enum.join(codes, "\n")}

    If you run out of backup codes, you can generate new
    ones from your account settings (this will invalidate
    any remaining old codes).
    """

    {:noreply, push_event(socket, "download_file", %{
      filename: "bezgelor-backup-codes.txt",
      content: content
    })}
  end
end
