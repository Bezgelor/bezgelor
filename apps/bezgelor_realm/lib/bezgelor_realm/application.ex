defmodule BezgelorRealm.Application do
  @moduledoc """
  OTP Application for the Realm/Auth Server.

  ## Overview

  The Realm Server handles:
  - Game token validation from STS server
  - Session key generation for World Server
  - Realm selection and info distribution

  Listens on port 23115 by default.

  ## Configuration

  Configure in `config/config.exs` or environment variables:

      config :bezgelor_realm,
        port: 23115

  Or set `REALM_PORT` environment variable.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:bezgelor_realm, :start_server, true) do
        port = Application.get_env(:bezgelor_realm, :port, 23115)
        Logger.info("Starting Realm Server on port #{port}")

        [
          # Start the packet registry if not already running
          BezgelorProtocol.PacketRegistry,

          # Start the TCP listener for realm connections
          {BezgelorProtocol.TcpListener,
           port: port,
           handler: BezgelorProtocol.Connection,
           handler_opts: [connection_type: :realm],
           name: :realm_listener}
        ]
      else
        Logger.info("Realm Server disabled (start_server: false)")
        []
      end

    opts = [strategy: :one_for_one, name: BezgelorRealm.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
