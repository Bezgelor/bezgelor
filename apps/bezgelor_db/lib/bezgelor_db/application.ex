defmodule BezgelorDb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BezgelorDb.Repo
    ]

    opts = [strategy: :one_for_one, name: BezgelorDb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
