defmodule Bezgelor.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    []
  end

  # Release configuration for production deployment
  # Includes all umbrella apps needed for the full server
  defp releases do
    [
      bezgelor_portal: [
        include_executables_for: [:unix],
        applications: [
          bezgelor_portal: :permanent,
          bezgelor_auth: :permanent,
          bezgelor_realm: :permanent,
          bezgelor_world: :permanent,
          bezgelor_db: :permanent,
          bezgelor_data: :permanent,
          bezgelor_core: :permanent,
          bezgelor_crypto: :permanent,
          bezgelor_protocol: :permanent
        ],
        rel_templates_path: "apps/bezgelor_portal/rel"
      ]
    ]
  end
end
