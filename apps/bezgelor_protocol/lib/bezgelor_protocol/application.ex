defmodule BezgelorProtocol.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Rate limiting for auth attempts
      {BezgelorProtocol.RateLimiter, clean_period: :timer.minutes(10)},
      BezgelorProtocol.PacketRegistry
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BezgelorProtocol.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
