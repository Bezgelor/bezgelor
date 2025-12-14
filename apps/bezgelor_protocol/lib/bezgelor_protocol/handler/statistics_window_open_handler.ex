defmodule BezgelorProtocol.Handler.StatisticsWindowOpenHandler do
  @moduledoc """
  Handler for ClientStatisticsWindowOpen packets.

  This telemetry packet is sent when the player opens a window/UI element.
  Currently just acknowledged without processing.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(_payload, state) do
    # Window open statistics - not critical, just acknowledge
    {:ok, state}
  end
end
