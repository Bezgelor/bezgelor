defmodule BezgelorRealm.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezgelor_realm,
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
      mod: {BezgelorRealm.Application, []}
    ]
  end

  defp deps do
    [
      {:bezgelor_protocol, in_umbrella: true},
      {:bezgelor_db, in_umbrella: true}
    ]
  end
end
