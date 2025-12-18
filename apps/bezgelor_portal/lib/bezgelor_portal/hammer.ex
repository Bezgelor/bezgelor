defmodule BezgelorPortal.Hammer do
  @moduledoc """
  Low-level rate limiter backend for the admin portal using Hammer v7.

  This module provides the underlying ETS-backed rate limiting infrastructure.
  For application-level rate limiting, use `BezgelorPortal.RateLimiter` which
  provides a higher-level API with preconfigured limits.

  ## Direct Usage

  For custom rate limits not covered by `RateLimiter`:

      case BezgelorPortal.Hammer.hit(key, window_ms, limit) do
        {:allow, _count} -> proceed_with_action()
        {:deny, _limit} -> handle_rate_limited()
      end

  ## Cleanup

  Hammer's ETS backend automatically cleans up expired entries. No manual
  cleanup process is required.

  ## See Also

  - `BezgelorPortal.RateLimiter` - High-level rate limiting for common operations
  """
  use Hammer, backend: :ets
end
