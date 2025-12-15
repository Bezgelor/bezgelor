defmodule BezgelorProtocol.Handler.DialogOpenedHandler do
  @moduledoc """
  Handler for ClientDialogOpened packets.

  Called when the client acknowledges that a dialog window has opened.
  This is typically sent after an NPC interaction or quest dialog.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(_payload, state) do
    # Zero-byte message - just an acknowledgment
    Logger.debug("Client acknowledged dialog opened")
    {:ok, state}
  end
end
