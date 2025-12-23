defmodule BezgelorPortalWeb.RegisterLive do
  @moduledoc """
  LiveView for new user registration.

  Handles account creation with email verification.
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorDb.Accounts
  alias BezgelorPortal.{Notifier, RateLimiter}

  @min_password_length 8

  require Logger

  def mount(_params, session, socket) do
    Logger.debug("RegisterLive mount called, connected=#{connected?(socket)}")

    # Redirect if already logged in (session is a map in LiveView, not a Plug.Conn)
    if session["current_account_id"] do
      {:ok, push_navigate(socket, to: ~p"/dashboard")}
    else
      # Use a simple map for the initial form to avoid changeset issues
      # Include terms_accepted to preserve checkbox state during validation
      form =
        to_form(
          %{
            "email" => "",
            "password" => "",
            "password_confirmation" => "",
            "terms_accepted" => "false"
          },
          as: :registration
        )

      # Store client IP during mount for rate limiting (can only access connect_info in mount)
      client_ip =
        if connected?(socket) do
          case get_connect_info(socket, :peer_data) do
            %{address: addr} -> format_ip(addr)
            _ -> "unknown"
          end
        else
          "unknown"
        end

      {:ok,
       assign(socket,
         form: form,
         password_strength: nil,
         check_errors: false,
         client_ip: client_ip
       )}
    end
  end

  def render(assigns) do
    ~H"""
    <h2 class="card-title text-2xl justify-center mb-6">Create Account</h2>

    <.form for={@form} phx-change="validate" phx-submit="register" class="space-y-4">
      <.input
        field={@form[:email]}
        type="email"
        label="Email"
        placeholder="you@example.com"
        required
        autocomplete="email"
        phx-debounce="300"
      />

      <div>
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          placeholder="At least 8 characters"
          required
          autocomplete="new-password"
          phx-debounce="300"
        />
        <.password_strength_indicator strength={@password_strength} />
      </div>

      <.input
        field={@form[:password_confirmation]}
        type="password"
        label="Confirm Password"
        placeholder="Confirm your password"
        required
        autocomplete="new-password"
      />

      <div class="flex gap-3">
        <input
          type="checkbox"
          id="terms_accepted"
          name="registration[terms_accepted]"
          value="true"
          checked={@form[:terms_accepted].value == "true"}
          class="checkbox checkbox-primary"
          required
        />
        <label for="terms_accepted" class="text-sm text-base-content/80 cursor-pointer">
          I agree to the <a href="/terms" class="link link-primary">Terms of Service</a><br />
          and <a href="/privacy" class="link link-primary">Privacy Policy</a>
        </label>
      </div>

      <div class="form-control mt-6">
        <.button type="submit" variant="primary" class="w-full">
          Create Account
        </.button>
      </div>
    </.form>

    <div class="divider">OR</div>

    <p class="text-center text-sm text-base-content/70">
      Already have an account? <.link href="/login" class="link link-primary">Sign in</.link>
    </p>
    """
  end

  attr :strength, :atom, default: nil

  defp password_strength_indicator(assigns) do
    ~H"""
    <div :if={@strength} class="mt-2">
      <div class="flex gap-1">
        <div class={[
          "h-1 flex-1 rounded",
          strength_color(@strength, 1)
        ]} />
        <div class={[
          "h-1 flex-1 rounded",
          strength_color(@strength, 2)
        ]} />
        <div class={[
          "h-1 flex-1 rounded",
          strength_color(@strength, 3)
        ]} />
        <div class={[
          "h-1 flex-1 rounded",
          strength_color(@strength, 4)
        ]} />
      </div>
      <p class={["text-xs mt-1", strength_text_color(@strength)]}>
        {strength_label(@strength)}
      </p>
    </div>
    """
  end

  defp strength_color(strength, level) do
    required =
      case strength do
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

  def handle_event("validate", %{"registration" => params}, socket) do
    Logger.debug("RegisterLive validate called with params: #{inspect(params)}")

    # Ensure terms_accepted has a value (browsers don't send unchecked checkboxes)
    params = Map.put_new(params, "terms_accepted", "false")

    # Only use changeset validation if check_errors is true (after submit attempt)
    # Otherwise just update the form values
    form =
      if socket.assigns.check_errors do
        changeset =
          params
          |> registration_changeset()
          |> Map.put(:action, :validate)

        to_form(changeset, as: :registration)
      else
        to_form(params, as: :registration)
      end

    password_strength = calculate_password_strength(params["password"] || "")

    {:noreply, assign(socket, form: form, password_strength: password_strength)}
  end

  # Catch-all for validate to prevent crashes
  def handle_event("validate", params, socket) do
    Logger.warning("RegisterLive validate catch-all called with: #{inspect(params)}")
    {:noreply, socket}
  end

  def handle_event("register", %{"registration" => params}, socket) do
    # Ensure terms_accepted has a value (browsers don't send unchecked checkboxes)
    params = Map.put_new(params, "terms_accepted", "false")

    # Check rate limit first (client_ip stored during mount)
    case RateLimiter.check_registration(socket.assigns.client_ip) do
      :ok ->
        do_register(params, socket)

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> put_flash(:error, "Too many registration attempts. Please try again later.")}
    end
  end

  defp do_register(params, socket) do
    changeset = registration_changeset(params)

    if changeset.valid? do
      email = params["email"]
      password = params["password"]

      case Accounts.register_account(email, password) do
        {:ok, account} ->
          # Send verification email
          Notifier.deliver_verification_email(account)

          {:noreply,
           socket
           |> put_flash(:info, "Account created! Please check your email to verify your account.")
           |> push_navigate(to: ~p"/login")}

        {:error, %Ecto.Changeset{} = changeset} ->
          # Check for duplicate email specifically
          errors = changeset.errors

          if Keyword.has_key?(errors, :email) do
            {:noreply,
             socket
             |> assign(form: to_form(changeset, as: :registration), check_errors: true)
             |> put_flash(:error, "An account with this email already exists.")}
          else
            {:noreply,
             socket
             |> assign(form: to_form(changeset, as: :registration), check_errors: true)}
          end
      end
    else
      {:noreply,
       assign(socket,
         form: to_form(%{changeset | action: :validate}, as: :registration),
         check_errors: true
       )}
    end
  end

  defp registration_changeset(params) do
    types = %{
      email: :string,
      password: :string,
      password_confirmation: :string,
      terms_accepted: :string
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:email, :password, :password_confirmation])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "must be a valid email address"
    )
    |> Ecto.Changeset.validate_length(:password,
      min: @min_password_length,
      message: "must be at least #{@min_password_length} characters"
    )
    |> validate_password_confirmation()
    |> validate_terms_accepted()
  end

  defp validate_terms_accepted(changeset) do
    terms = Ecto.Changeset.get_field(changeset, :terms_accepted)

    if terms == "true" do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :terms_accepted, "must be accepted")
    end
  end

  defp validate_password_confirmation(changeset) do
    password = Ecto.Changeset.get_field(changeset, :password)
    confirmation = Ecto.Changeset.get_field(changeset, :password_confirmation)

    if password && confirmation && password != confirmation do
      Ecto.Changeset.add_error(changeset, :password_confirmation, "does not match password")
    else
      changeset
    end
  end

  defp calculate_password_strength(password) when byte_size(password) == 0, do: nil

  defp calculate_password_strength(password) do
    score = 0

    # Length scoring
    score = score + min(div(String.length(password), 4), 3)

    # Character variety
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

  defp format_ip(ip_tuple) when is_tuple(ip_tuple) do
    ip_tuple |> Tuple.to_list() |> Enum.join(".")
  end

  defp format_ip(_), do: "unknown"
end
