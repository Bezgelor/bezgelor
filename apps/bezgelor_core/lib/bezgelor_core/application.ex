defmodule BezgelorCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # PubSub for real-time event broadcasting (achievements, etc.)
      {Phoenix.PubSub, name: BezgelorCore.PubSub}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BezgelorCore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
