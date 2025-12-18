defmodule BezgelorProtocol.RateLimiter do
  @moduledoc """
  Rate limiter for protocol-level auth attempts using Hammer v7.
  """
  use Hammer, backend: :ets
end
