defmodule BezgelorPortal.Hammer do
  @moduledoc """
  Rate limiter for portal using Hammer v7.
  """
  use Hammer, backend: :ets
end
