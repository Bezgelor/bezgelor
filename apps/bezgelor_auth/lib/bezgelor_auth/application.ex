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
        host: "0.0.0.0",
        port: 6600

  Or set `AUTH_HOST` and `AUTH_PORT` environment variables.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:bezgelor_auth, :start_server, true) do
        host = Application.get_env(:bezgelor_auth, :host, "0.0.0.0")
        port = Application.get_env(:bezgelor_auth, :port, 6600)
        Logger.info("Starting STS Auth Server on #{host}:#{port}")

        socket_opts = build_socket_opts(host, port)

        [
          # Start the STS protocol listener for auth connections
          # WildStar client (via ClientConnector) uses HTTP-style STS/1.0 protocol
          :ranch.child_spec(
            :sts_listener,
            :ranch_tcp,
            socket_opts,
            BezgelorAuth.Sts.Connection,
            []
          )
        ]
      else
        Logger.info("Auth Server disabled (start_server: false)")
        []
      end

    opts = [strategy: :one_for_one, name: BezgelorAuth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp build_socket_opts(host, port) do
    base_opts = %{socket_opts: [port: port]}

    case parse_host(host) do
      {:ok, ip_tuple} ->
        %{base_opts | socket_opts: [port: port, ip: ip_tuple]}

      :error ->
        base_opts
    end
  end

  defp parse_host(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip_tuple} -> {:ok, ip_tuple}
      {:error, _} -> :error
    end
  end
end
