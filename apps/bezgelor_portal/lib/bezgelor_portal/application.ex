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
      # Rate limiting for auth actions
      {BezgelorPortal.Hammer, clean_period: :timer.minutes(10)},
      # Encryption vault for TOTP secrets
      BezgelorPortal.Vault,
      # Log buffer for admin log viewer
      BezgelorPortal.LogBuffer,
      # Task supervisor for async tasks (must start before RollupScheduler)
      {Task.Supervisor, name: BezgelorPortal.TaskSupervisor},
      # Telemetry metrics collection and rollup
      BezgelorPortal.TelemetryCollector,
      BezgelorPortal.RollupScheduler,
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
