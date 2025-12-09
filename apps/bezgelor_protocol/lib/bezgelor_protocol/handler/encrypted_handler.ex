defmodule BezgelorProtocol.Handler.EncryptedHandler do
  @moduledoc """
  Handler for ClientEncrypted packets.

  This handler decrypts the inner packet and re-dispatches it
  through the packet processing pipeline.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(payload, state) do
    Logger.debug("EncryptedHandler: received #{byte_size(payload)} bytes")
    # TODO: Decrypt and re-dispatch inner packet
    {:ok, state}
  end
end
