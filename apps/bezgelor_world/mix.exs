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
      deps: deps(),
      aliases: aliases(),
      # Exclude integration tests by default (they need server running)
      # Run with `mix test --include integration` to include them
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "test.all": :test, "test.integration": :test],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BezgelorWorld.Application, []}
    ]
  end

  defp aliases do
    [
      # Run all tests including integration tests
      "test.all": ["test --include integration --include database"],
      # Run only integration tests
      "test.integration": ["test --include integration --only integration"]
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
