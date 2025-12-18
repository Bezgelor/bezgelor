defmodule BezgelorProtocol.RateLimiter do
  @moduledoc """
  Rate limiter for protocol-level authentication attempts using Hammer v7.

  This module provides ETS-backed rate limiting for the game protocol authentication
  flow. Rate limiting prevents brute-force attacks on player accounts.

  ## Rate Limits

  Authentication is limited to **5 attempts per minute per IP address**
  (configured in `AuthHandler`).

  ## Usage

  The rate limiter is called from `AuthHandler` before processing auth:

      case BezgelorProtocol.RateLimiter.hit("auth:\#{client_ip}", 60_000, 5) do
        {:allow, _count} -> process_authentication()
        {:deny, _limit} -> deny_for_rate_limit()
      end

  ## Cleanup

  Hammer's ETS backend automatically cleans up expired entries. No manual
  cleanup process is required.

  ## Configuration

  Uses ETS backend for in-memory storage. For persistent or distributed rate
  limiting, configure a Redis backend in the Hammer configuration.
  """
  use Hammer, backend: :ets
end
