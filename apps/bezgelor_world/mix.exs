defmodule BezgelorWorld.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezgelor_world,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BezgelorWorld.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bezgelor_protocol, in_umbrella: true},
      {:bezgelor_db, in_umbrella: true},
      {:bezgelor_core, in_umbrella: true},
      {:bezgelor_data, in_umbrella: true}
    ]
  end
end
