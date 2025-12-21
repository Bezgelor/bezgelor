defmodule BezgelorWorld.ProcessLookup do
  @moduledoc """
  Thin helper for common Registry operations.

  Provides convenience functions for listing and counting processes
  in a Registry. This module does NOT abstract Registry - it's a
  utility to avoid repetitive select/match patterns.

  ## Usage

      # List all world instances
      ProcessLookup.list_with_meta(BezgelorWorld.WorldRegistry)

      # Count event managers
      ProcessLookup.count(BezgelorWorld.EventRegistry)
  """

  @doc """
  List all processes in a registry with their keys and metadata.

  Returns `[{key, pid, metadata}, ...]`.
  """
  @spec list_with_meta(atom()) :: [{term(), pid(), term()}]
  def list_with_meta(registry) do
    match_pattern = {:"$1", :"$2", :"$3"}
    guards = []
    body = [{{:"$1", :"$2", :"$3"}}]

    Registry.select(registry, [{match_pattern, guards, body}])
  end

  @doc """
  Count the number of registered processes in a registry.
  """
  @spec count(atom()) :: non_neg_integer()
  def count(registry) do
    match_pattern = {:_, :_, :_}
    guards = []
    body = [true]

    Registry.select(registry, [{match_pattern, guards, body}])
    |> length()
  end

  @doc """
  Lookup a process by key, returning the pid or nil.
  """
  @spec whereis(atom(), term()) :: pid() | nil
  def whereis(registry, key) do
    case Registry.lookup(registry, key) do
      [{pid, _metadata}] -> pid
      [] -> nil
    end
  end
end
