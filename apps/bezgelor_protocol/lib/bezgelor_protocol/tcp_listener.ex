defmodule BezgelorProtocol.TcpListener do
  @moduledoc """
  TCP listener wrapper around Ranch.

  ## Overview

  Manages a Ranch listener that accepts TCP connections and spawns
  connection handler processes.

  ## Example

      # Start a listener
      {:ok, _} = TcpListener.start_link(
        port: 6600,
        handler: MyConnectionHandler,
        name: :auth_listener
      )

      # Get the actual port (useful when port: 0)
      port = TcpListener.get_port(:auth_listener)
  """

  require Logger

  @doc """
  Returns a child specification for supervision.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Start a TCP listener.

  ## Options

  - `:port` - Port to listen on (required, use 0 for random)
  - `:handler` - Connection handler module (required)
  - `:name` - Listener name atom (required)
  - `:num_acceptors` - Number of acceptor processes (default: 10)
  - `:handler_opts` - Options passed to handler (default: [])
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    port = Keyword.fetch!(opts, :port)
    handler = Keyword.fetch!(opts, :handler)
    name = Keyword.fetch!(opts, :name)
    num_acceptors = Keyword.get(opts, :num_acceptors, 10)
    handler_opts = Keyword.get(opts, :handler_opts, [])

    transport_opts = %{
      socket_opts: [port: port],
      num_acceptors: num_acceptors
    }

    Logger.info("Starting TCP listener #{name} on port #{port}")

    :ranch.start_listener(
      name,
      :ranch_tcp,
      transport_opts,
      handler,
      handler_opts
    )
  end

  @doc "Get the port a listener is bound to."
  @spec get_port(atom()) :: non_neg_integer()
  def get_port(name) do
    :ranch.get_port(name)
  end

  @doc "Stop a listener."
  @spec stop(atom()) :: :ok
  def stop(name) do
    :ranch.stop_listener(name)
  end

  @doc "Get connection count for a listener."
  @spec connection_count(atom()) :: non_neg_integer()
  def connection_count(name) do
    :ranch.procs(name, :connections) |> length()
  end
end
