defmodule BezgelorWorld.Application do
  @moduledoc """
  OTP Application for the World Server.

  ## Overview

  The World Server handles:
  - Session key validation from Realm Server
  - Character list management (create, select, delete)
  - World entry (Phase 6)

  Listens on port 24000 by default.

  ## Configuration

  Configure in `config/config.exs` or environment variables:

      config :bezgelor_world,
        port: 24000

  Or set `WORLD_PORT` environment variable.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Always start WorldManager, CreatureManager, and Zone infrastructure
    base_children = [
      BezgelorWorld.WorldManager,
      BezgelorWorld.CreatureManager,
      BezgelorWorld.BuffManager,
      # Dynamic supervisor for zone instances
      BezgelorWorld.Zone.InstanceSupervisor
    ]

    server_children =
      if Application.get_env(:bezgelor_world, :start_server, true) do
        port = Application.get_env(:bezgelor_world, :port, 24000)
        Logger.info("Starting World Server on port #{port}")

        [
          # Start the packet registry if not already running
          BezgelorProtocol.PacketRegistry,

          # Start the TCP listener for world connections
          {BezgelorProtocol.TcpListener,
           port: port,
           handler: BezgelorProtocol.Connection,
           handler_opts: [connection_type: :world],
           name: :world_listener}
        ]
      else
        Logger.info("World Server disabled (start_server: false)")
        []
      end

    children = base_children ++ server_children
    opts = [strategy: :one_for_one, name: BezgelorWorld.Supervisor]

    result = Supervisor.start_link(children, opts)

    # Initialize zones after supervisor is running
    case result do
      {:ok, _pid} ->
        # Spawn task to initialize zones (non-blocking)
        Task.start(fn ->
          # Small delay to ensure all processes are ready
          Process.sleep(100)
          BezgelorWorld.Zone.Manager.initialize_zones()
        end)

      _ ->
        :ok
    end

    result
  end
end
