defmodule BezgelorDev.MixProject do
  use Mix.Project

  def project do
    [
      app: :bezgelor_dev,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BezgelorDev.Application, []}
    ]
  end

  defp deps do
    [
      # JSON encoding
      {:jason, "~> 1.4"}
      # Note: bezgelor_dev has no umbrella dependencies to avoid circular deps.
      # It uses BezgelorProtocol.Opcode via runtime calls, not compile-time deps.
    ]
  end
end
