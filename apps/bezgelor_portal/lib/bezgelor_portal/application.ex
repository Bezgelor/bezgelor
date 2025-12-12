defmodule BezgelorPortal.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BezgelorPortalWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:bezgelor_portal, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BezgelorPortal.PubSub},
      # Encryption vault for TOTP secrets
      BezgelorPortal.Vault,
      # Start to serve requests, typically the last entry
      BezgelorPortalWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BezgelorPortal.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BezgelorPortalWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
