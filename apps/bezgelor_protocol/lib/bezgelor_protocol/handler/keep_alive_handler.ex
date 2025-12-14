defmodule BezgelorProtocol.Handler.KeepAliveHandler do
  @moduledoc """
  Handles ClientPregameKeepAlive packets (opcode 0x0241).

  The client sends this every 60 seconds while on the CharacterSelect or RealmSelect
  screen to keep the TCP socket alive when no other messages are being sent.

  This handler just acknowledges the packet - no response is needed.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(_payload, state) do
    Logger.debug("KeepAliveHandler: heartbeat received")
    {:ok, state}
  end
end
