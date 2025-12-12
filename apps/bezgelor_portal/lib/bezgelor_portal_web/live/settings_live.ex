defmodule BezgelorPortalWeb.SettingsLive do
  @moduledoc """
  LiveView for account settings management.

  Provides a tabbed interface for:
  - Profile: Email management
  - Security: Password change, TOTP setup
  - Account: Account deletion
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Accounts
  alias BezgelorCrypto.Password
  alias BezgelorPortal.{Auth, Notifier, RateLimiter}

  @min_password_length 8

  def mount(_params, _session, socket) do
    account = socket.assigns.current_account

    {:ok,
     assign(socket,
       page_title: "Account Settings",
       active_tab: "profile",
       # Profile tab
       email_form: to_form(%{"new_email" => ""}, as: :email_change),
       email_error: nil,
       email_success: nil,
       # Security tab
       password_form: to_form(%{
         "current_password" => "",
         "new_password" => "",
         "new_password_confirmation" => ""
       }, as: :password_change),
       password_error: nil,
       password_success: nil,
       password_strength: nil,
       totp_enabled: account.totp_enabled_at != nil,
       # Account tab
       delete_form: to_form(%{"confirm_email" => ""}, as: :delete_account),
       delete_error: nil,
       show_delete_modal: false
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto max-w-4xl px-4 py-8">
      <h1 class="text-3xl font-bold mb-8">Account Settings</h1>

      <div class="tabs tabs-boxed mb-8">
        <button
          class={["tab", @active_tab == "profile" && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="profile"
        >
          <.icon name="hero-user" class="size-4 mr-2" />
          Profile
        </button>
        <button
          class={["tab", @active_tab == "security" && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="security"
        >
          <.icon name="hero-shield-check" class="size-4 mr-2" />
          Security
        </button>
        <button
          class={["tab", @active_tab == "account" && "tab-active"]}
          phx-click="switch_tab"
          phx-value-tab="account"
        >
          <.icon name="hero-cog-6-tooth" class="size-4 mr-2" />
          Account
        </button>
      </div>

      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <%= case @active_tab do %>
            <% "profile" -> %>
              <.profile_tab
                account={@current_account}
                form={@email_form}
                error={@email_error}
                success={@email_success}
              />
            <% "security" -> %>
              <.security_tab
                form={@password_form}
                error={@password_error}
                success={@password_success}
                password_strength={@password_strength}
                totp_enabled={@totp_enabled}
              />
            <% "account" -> %>
              <.account_tab
                account={@current_account}
                form={@delete_form}
                error={@delete_error}
                show_delete_modal={@show_delete_modal}
              />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Profile Tab
  attr :account, :map, required: true
  attr :form, :map, required: true
  attr :error, :string, default: nil
  attr :success, :string, default: nil

  defp profile_tab(assigns) do
    ~H"""
    <div>
      <h2 class="card-title text-xl mb-6">Profile Settings</h2>

      <div class="space-y-6">
        <div class="form-control">
          <label class="label">
            <span class="label-text font-medium">Current Email</span>
          </label>
          <div class="flex items-center gap-3">
            <span class="text-lg">{@account.email}</span>
            <%= if @account.email_verified_at do %>
              <span class="badge badge-success gap-1">
                <.icon name="hero-check-circle" class="size-3" />
                Verified
              </span>
            <% else %>
              <span class="badge badge-warning gap-1">
                <.icon name="hero-exclamation-triangle" class="size-3" />
                Unverified
              </span>
            <% end %>
          </div>
        </div>

        <div class="divider">Change Email</div>

        <.form for={@form} phx-submit="change_email" class="space-y-4">
          <.input
            field={@form[:new_email]}
            type="email"
            label="New Email Address"
            placeholder="Enter your new email"
            required
          />

          <div :if={@error} class="alert alert-error">
            <.icon name="hero-exclamation-circle" class="size-5" />
            <span>{@error}</span>
          </div>

          <div :if={@success} class="alert alert-success">
            <.icon name="hero-check-circle" class="size-5" />
            <span>{@success}</span>
          </div>

          <div class="form-control">
            <.button type="submit" variant="primary">
              <.icon name="hero-envelope" class="size-4 mr-2" />
              Request Email Change
            </.button>
          </div>
          <p class="text-sm text-base-content/60">
            A verification link will be sent to your new email address.
          </p>
        </.form>
      </div>
    </div>
    """
  end

  # Security Tab
  attr :form, :map, required: true
  attr :error, :string, default: nil
  attr :success, :string, default: nil
  attr :password_strength, :atom, default: nil
  attr :totp_enabled, :boolean, required: true

  defp security_tab(assigns) do
    ~H"""
    <div>
      <h2 class="card-title text-xl mb-6">Security Settings</h2>

      <div class="space-y-8">
        <div>
          <h3 class="font-semibold text-lg mb-4">Change Password</h3>

          <.form for={@form} phx-change="validate_password" phx-submit="change_password" class="space-y-4">
            <.input
              field={@form[:current_password]}
              type="password"
              label="Current Password"
              placeholder="Enter your current password"
              required
              autocomplete="current-password"
            />

            <div>
              <.input
                field={@form[:new_password]}
                type="password"
                label="New Password"
                placeholder="At least 8 characters"
                required
                autocomplete="new-password"
                phx-debounce="300"
              />
              <.password_strength_indicator strength={@password_strength} />
            </div>

            <.input
              field={@form[:new_password_confirmation]}
              type="password"
              label="Confirm New Password"
              placeholder="Confirm your new password"
              required
              autocomplete="new-password"
            />

            <div :if={@error} class="alert alert-error">
              <.icon name="hero-exclamation-circle" class="size-5" />
              <span>{@error}</span>
            </div>

            <div :if={@success} class="alert alert-success">
              <.icon name="hero-check-circle" class="size-5" />
              <span>{@success}</span>
            </div>

            <div class="form-control">
              <.button type="submit" variant="primary">
                <.icon name="hero-key" class="size-4 mr-2" />
                Update Password
              </.button>
            </div>
          </.form>
        </div>

        <div class="divider">Two-Factor Authentication</div>

        <div class="flex items-center justify-between">
          <div>
            <h3 class="font-semibold">Authenticator App</h3>
            <p class="text-sm text-base-content/60">
              Add an extra layer of security to your account.
            </p>
          </div>
          <%= if @totp_enabled do %>
            <div class="flex items-center gap-3">
              <span class="badge badge-success gap-1">
                <.icon name="hero-check-circle" class="size-3" />
                Enabled
              </span>
              <.link href={~p"/settings/totp/disable"} class="btn btn-sm btn-outline btn-error">
                Disable
              </.link>
            </div>
          <% else %>
            <.link href={~p"/settings/totp/setup"} class="btn btn-primary btn-sm">
              <.icon name="hero-device-phone-mobile" class="size-4 mr-2" />
              Set Up
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Account Tab
  attr :account, :map, required: true
  attr :form, :map, required: true
  attr :error, :string, default: nil
  attr :show_delete_modal, :boolean, required: true

  defp account_tab(assigns) do
    ~H"""
    <div>
      <h2 class="card-title text-xl mb-6">Account Settings</h2>

      <div class="space-y-6">
        <div class="form-control">
          <label class="label">
            <span class="label-text font-medium">Account Created</span>
          </label>
          <span>{Calendar.strftime(@account.inserted_at, "%B %d, %Y")}</span>
        </div>

        <div class="divider">Danger Zone</div>

        <div class="border border-error rounded-lg p-4">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="font-semibold text-error">Delete Account</h3>
              <p class="text-sm text-base-content/60">
                Permanently delete your account and all associated data.
              </p>
            </div>
            <button
              class="btn btn-outline btn-error"
              phx-click="show_delete_modal"
            >
              <.icon name="hero-trash" class="size-4 mr-2" />
              Delete Account
            </button>
          </div>
        </div>
      </div>

      <.delete_modal
        :if={@show_delete_modal}
        account={@account}
        form={@form}
        error={@error}
      />
    </div>
    """
  end

  # Delete Confirmation Modal
  attr :account, :map, required: true
  attr :form, :map, required: true
  attr :error, :string, default: nil

  defp delete_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box">
        <h3 class="font-bold text-lg text-error">Delete Account</h3>
        <p class="py-4">
          This action is <strong>irreversible</strong>. All your data, including
          characters, will be permanently deleted.
        </p>

        <.form for={@form} phx-submit="delete_account">
          <p class="text-sm mb-2">
            Type <strong>{@account.email}</strong> to confirm:
          </p>
          <.input
            field={@form[:confirm_email]}
            type="email"
            placeholder="Enter your email address"
            required
          />

          <div :if={@error} class="alert alert-error mt-4">
            <.icon name="hero-exclamation-circle" class="size-5" />
            <span>{@error}</span>
          </div>

          <div class="modal-action">
            <button type="button" class="btn" phx-click="hide_delete_modal">
              Cancel
            </button>
            <button type="submit" class="btn btn-error">
              <.icon name="hero-trash" class="size-4 mr-2" />
              Delete My Account
            </button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop" phx-click="hide_delete_modal" />
    </div>
    """
  end

  # Password strength indicator component
  attr :strength, :atom, default: nil

  defp password_strength_indicator(assigns) do
    ~H"""
    <div :if={@strength} class="mt-2">
      <div class="flex gap-1">
        <div class={["h-1 flex-1 rounded", strength_color(@strength, 1)]} />
        <div class={["h-1 flex-1 rounded", strength_color(@strength, 2)]} />
        <div class={["h-1 flex-1 rounded", strength_color(@strength, 3)]} />
        <div class={["h-1 flex-1 rounded", strength_color(@strength, 4)]} />
      </div>
      <p class={["text-xs mt-1", strength_text_color(@strength)]}>
        {strength_label(@strength)}
      </p>
    </div>
    """
  end

  defp strength_color(strength, level) do
    required = case strength do
      :weak -> 1
      :fair -> 2
      :good -> 3
      :strong -> 4
      _ -> 0
    end

    if level <= required do
      case strength do
        :weak -> "bg-error"
        :fair -> "bg-warning"
        :good -> "bg-info"
        :strong -> "bg-success"
        _ -> "bg-base-300"
      end
    else
      "bg-base-300"
    end
  end

  defp strength_text_color(strength) do
    case strength do
      :weak -> "text-error"
      :fair -> "text-warning"
      :good -> "text-info"
      :strong -> "text-success"
      _ -> "text-base-content/50"
    end
  end

  defp strength_label(strength) do
    case strength do
      :weak -> "Weak - add more characters or variety"
      :fair -> "Fair - consider adding symbols or numbers"
      :good -> "Good password"
      :strong -> "Strong password"
      _ -> ""
    end
  end

  # Event Handlers

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("change_email", %{"email_change" => %{"new_email" => new_email}}, socket) do
    account = socket.assigns.current_account

    cond do
      String.downcase(new_email) == String.downcase(account.email) ->
        {:noreply, assign(socket, email_error: "New email must be different from current email.")}

      not valid_email?(new_email) ->
        {:noreply, assign(socket, email_error: "Please enter a valid email address.")}

      Accounts.email_exists?(new_email) ->
        {:noreply, assign(socket, email_error: "This email is already in use.")}

      true ->
        # Check rate limit
        case RateLimiter.check_verification_resend(account.email) do
          :ok ->
            # Generate email change token and send verification
            Notifier.deliver_email_change_verification(account, new_email)

            {:noreply,
             socket
             |> assign(
               email_error: nil,
               email_success: "Verification email sent to #{new_email}. Please check your inbox.",
               email_form: to_form(%{"new_email" => ""}, as: :email_change)
             )}

          {:error, :rate_limited} ->
            {:noreply, assign(socket, email_error: "Too many requests. Please try again later.")}
        end
    end
  end

  def handle_event("validate_password", %{"password_change" => params}, socket) do
    strength = calculate_password_strength(params["new_password"] || "")
    {:noreply, assign(socket, password_strength: strength)}
  end

  def handle_event("change_password", %{"password_change" => params}, socket) do
    account = socket.assigns.current_account
    current_password = params["current_password"]
    new_password = params["new_password"]
    confirmation = params["new_password_confirmation"]

    cond do
      not Password.verify_password(account.email, current_password, account.salt, account.verifier) ->
        {:noreply, assign(socket, password_error: "Current password is incorrect.", password_success: nil)}

      String.length(new_password) < @min_password_length ->
        {:noreply, assign(socket, password_error: "New password must be at least #{@min_password_length} characters.", password_success: nil)}

      new_password != confirmation ->
        {:noreply, assign(socket, password_error: "New passwords do not match.", password_success: nil)}

      true ->
        case Accounts.update_password(account, new_password) do
          {:ok, _account} ->
            {:noreply,
             socket
             |> assign(
               password_error: nil,
               password_success: "Password updated successfully.",
               password_form: to_form(%{
                 "current_password" => "",
                 "new_password" => "",
                 "new_password_confirmation" => ""
               }, as: :password_change),
               password_strength: nil
             )}

          {:error, _changeset} ->
            {:noreply, assign(socket, password_error: "Failed to update password. Please try again.", password_success: nil)}
        end
    end
  end

  def handle_event("show_delete_modal", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: true)}
  end

  def handle_event("hide_delete_modal", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: false, delete_error: nil)}
  end

  def handle_event("delete_account", %{"delete_account" => %{"confirm_email" => confirm_email}}, socket) do
    account = socket.assigns.current_account

    if String.downcase(confirm_email) == String.downcase(account.email) do
      case Accounts.soft_delete_account(account) do
        {:ok, _account} ->
          {:noreply,
           socket
           |> put_flash(:info, "Your account has been scheduled for deletion.")
           |> redirect(to: ~p"/logout")}

        {:error, _changeset} ->
          {:noreply, assign(socket, delete_error: "Failed to delete account. Please try again.")}
      end
    else
      {:noreply, assign(socket, delete_error: "Email does not match. Please type your email exactly.")}
    end
  end

  # Helpers

  defp valid_email?(email) do
    Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, email)
  end

  defp calculate_password_strength(password) when byte_size(password) == 0, do: nil

  defp calculate_password_strength(password) do
    score = 0
    score = score + min(div(String.length(password), 4), 3)
    score = if Regex.match?(~r/[a-z]/, password), do: score + 1, else: score
    score = if Regex.match?(~r/[A-Z]/, password), do: score + 1, else: score
    score = if Regex.match?(~r/[0-9]/, password), do: score + 1, else: score
    score = if Regex.match?(~r/[^a-zA-Z0-9]/, password), do: score + 2, else: score

    cond do
      score < 3 -> :weak
      score < 5 -> :fair
      score < 7 -> :good
      true -> :strong
    end
  end
end
