defmodule BezgelorAuth.Application do
  @moduledoc """
  OTP Application for the STS Auth Server.

  ## Overview

  The Auth Server (STS) handles:
  - SRP6 password authentication
  - Game token generation
  - Initial client connection on port 6600

  ## Children

  - TCP Listener: Ranch acceptor on port 6600
  - Each connection spawns a BezgelorProtocol.Connection process

  ## Configuration

  Configure in `config/config.exs` or environment variables:

      config :bezgelor_auth,
        port: 6600

  Or set `AUTH_PORT` environment variable.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:bezgelor_auth, :start_server, true) do
        port = Application.get_env(:bezgelor_auth, :port, 6600)
        Logger.info("Starting Auth Server on port #{port}")

        [
          # Start the packet registry
          BezgelorProtocol.PacketRegistry,

          # Start the TCP listener for auth connections
          {BezgelorProtocol.TcpListener,
           port: port,
           handler: BezgelorProtocol.Connection,
           handler_opts: [connection_type: :auth],
           name: :auth_listener}
        ]
      else
        Logger.info("Auth Server disabled (start_server: false)")
        []
      end

    opts = [strategy: :one_for_one, name: BezgelorAuth.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
