defmodule BezgelorProtocol.Handler.RealmHandler do
  @moduledoc """
  Handler for ClientHelloRealm packets.

  This handler processes realm server connection requests
  from authenticated clients.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(payload, state) do
    Logger.debug("RealmHandler: received #{byte_size(payload)} bytes")
    # TODO: Validate session ticket and initialize realm connection
    {:ok, state}
  end
end
