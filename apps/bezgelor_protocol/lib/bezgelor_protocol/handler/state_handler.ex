defmodule BezgelorProtocol.Handler.StateHandler do
  @moduledoc """
  Handles ClientState (opcode 0x0000) packets.

  This is a connection state notification from the client that requires
  no server response. We simply acknowledge and ignore it.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(_payload, state) do
    Logger.debug("StateHandler: received ClientState (ignored)")
    {:ok, state}
  end
end
