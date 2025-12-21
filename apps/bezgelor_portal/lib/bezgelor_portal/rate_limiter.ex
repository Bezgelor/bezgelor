defmodule BezgelorPortal.RateLimiter do
  @moduledoc """
  Rate limiting for portal actions using Hammer.

  Provides rate limiting for security-sensitive operations:
  - Registration: 5 attempts per hour per IP
  - Login: 10 attempts per 15 minutes per IP
  - Password reset: 3 attempts per hour per email

  ## Usage

      case RateLimiter.check_registration(client_ip) do
        :ok -> # proceed with registration
        {:error, :rate_limited} -> # show error
      end
  """

  @registration_limit 5
  # 1 hour
  @registration_window_ms 60_000 * 60

  @login_limit 10
  # 15 minutes
  @login_window_ms 60_000 * 15

  @password_reset_limit 3
  # 1 hour
  @password_reset_window_ms 60_000 * 60

  @doc """
  Check if a registration attempt is allowed for the given IP.

  Allows #{@registration_limit} registration attempts per hour per IP address.
  """
  @spec check_registration(String.t()) :: :ok | {:error, :rate_limited}
  def check_registration(ip) when is_binary(ip) do
    check_rate("registration:#{ip}", @registration_limit, @registration_window_ms)
  end

  @doc """
  Check if a login attempt is allowed for the given IP.

  Allows #{@login_limit} login attempts per 15 minutes per IP address.
  """
  @spec check_login(String.t()) :: :ok | {:error, :rate_limited}
  def check_login(ip) when is_binary(ip) do
    check_rate("login:#{ip}", @login_limit, @login_window_ms)
  end

  @doc """
  Check if a password reset request is allowed for the given email.

  Allows #{@password_reset_limit} password reset requests per hour per email.
  """
  @spec check_password_reset(String.t()) :: :ok | {:error, :rate_limited}
  def check_password_reset(email) when is_binary(email) do
    check_rate(
      "password_reset:#{String.downcase(email)}",
      @password_reset_limit,
      @password_reset_window_ms
    )
  end

  @doc """
  Check if an email verification resend is allowed for the given email.

  Uses same limits as password reset.
  """
  @spec check_verification_resend(String.t()) :: :ok | {:error, :rate_limited}
  def check_verification_resend(email) when is_binary(email) do
    check_rate(
      "verification_resend:#{String.downcase(email)}",
      @password_reset_limit,
      @password_reset_window_ms
    )
  end

  defp check_rate(key, limit, window_ms) do
    case BezgelorPortal.Hammer.hit(key, window_ms, limit) do
      {:allow, _info} -> :ok
      {:deny, _info} -> {:error, :rate_limited}
    end
  end
end
