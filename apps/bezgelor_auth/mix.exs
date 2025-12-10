defmodule BezgelorAuth.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezgelor_auth,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BezgelorAuth.Application, []}
    ]
  end

  defp deps do
    [
      {:bezgelor_protocol, in_umbrella: true},
      {:bezgelor_db, in_umbrella: true},
      {:bezgelor_crypto, in_umbrella: true}
    ]
  end
end
