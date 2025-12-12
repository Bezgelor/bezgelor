defmodule BezgelorDev.Application do
  @moduledoc """
  OTP Application for the development capture system.

  Only starts child processes when dev mode is enabled. When mode is
  `:disabled`, no processes are started, ensuring zero overhead.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = build_children()

    if length(children) > 0 do
      Logger.info("BezgelorDev starting in #{BezgelorDev.mode()} mode")
    end

    opts = [strategy: :one_for_one, name: BezgelorDev.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp build_children do
    case BezgelorDev.mode() do
      :disabled ->
        # No children when disabled - zero overhead
        []

      mode when mode in [:logging, :interactive] ->
        # DevCapture handles all capture events
        [BezgelorDev.DevCapture]
    end
  end
end
