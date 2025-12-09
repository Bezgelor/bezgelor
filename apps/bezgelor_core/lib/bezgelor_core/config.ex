defmodule BezgelorCore.Config do
  @moduledoc """
  Configuration access utilities for Bezgelor applications.

  ## Overview

  This module provides a consistent interface for accessing application
  configuration. It wraps `Application.get_env/3` with additional features:

  - `get/3` - Get config with optional default
  - `get!/2` - Get config or raise if missing

  ## Example

      # In config/config.exs:
      config :bezgelor_core,
        server_name: "Bezgelor",
        max_players: 1000

      # In code:
      BezgelorCore.Config.get(:bezgelor_core, :server_name)
      # => "Bezgelor"
  """

  @doc """
  Get a configuration value for the given application and key.

  Returns `default` if the key is not found (defaults to `nil`).
  """
  @spec get(atom(), atom(), term()) :: term()
  def get(app, key, default \\ nil) do
    Application.get_env(app, key, default)
  end

  @doc """
  Get a configuration value, raising if not found.

  Raises `KeyError` if the configuration key does not exist.
  """
  @spec get!(atom(), atom()) :: term()
  def get!(app, key) do
    case Application.fetch_env(app, key) do
      {:ok, value} -> value
      :error -> raise KeyError, key: key, term: app
    end
  end
end
