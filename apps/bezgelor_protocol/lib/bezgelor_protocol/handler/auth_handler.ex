defmodule BezgelorProtocol.Handler.AuthHandler do
  @moduledoc """
  Handler for ClientHelloAuth packets.

  This handler processes the initial authentication request from clients
  and starts the SRP6 authentication handshake.
  """

  @behaviour BezgelorProtocol.Handler

  require Logger

  @impl true
  def handle(payload, state) do
    Logger.debug("AuthHandler: received #{byte_size(payload)} bytes")
    # TODO: Parse ClientHelloAuth and start SRP6 handshake
    {:ok, state}
  end
end
