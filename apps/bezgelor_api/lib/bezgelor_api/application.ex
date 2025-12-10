defmodule BezgelorApi.Application do
  @moduledoc """
  OTP Application for the REST API server.

  ## Overview

  The API server provides HTTP endpoints for:
  - Server status monitoring
  - Zone information
  - Player statistics

  Listens on port 4000 by default.

  ## Configuration

  Configure in `config/config.exs` or environment variables:

      config :bezgelor_api,
        port: 4000

  Or set `API_PORT` environment variable.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:bezgelor_api, :port, 4000)
    start_server = Application.get_env(:bezgelor_api, :start_server, true)

    children =
      if start_server do
        Logger.info("Starting API Server on port #{port}")

        [
          {Plug.Cowboy, scheme: :http, plug: BezgelorApi.Router, options: [port: port]}
        ]
      else
        Logger.info("API Server disabled (start_server: false)")
        []
      end

    opts = [strategy: :one_for_one, name: BezgelorApi.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
