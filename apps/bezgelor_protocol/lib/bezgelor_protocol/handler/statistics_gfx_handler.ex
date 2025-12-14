defmodule BezgelorProtocol.Handler.StatisticsGfxHandler do
  @moduledoc """
  Handler for ClientStatisticsGfx packets.

  This telemetry packet contains graphics/rendering statistics from the client.
  Currently just acknowledged without processing.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(_payload, state) do
    # GFX statistics - not critical, just acknowledge
    {:ok, state}
  end
end
