defmodule BezgelorWorld.Instance.Registry do
  @moduledoc """
  Registry helpers for instance processes.

  Provides convenience functions for registering, looking up, and
  managing instance processes through the Registry.
  """

  @registry __MODULE__

  @doc """
  Returns the registry name.
  """
  def registry_name, do: @registry

  @doc """
  Returns a via tuple for registering/looking up an instance by its GUID.
  """
  @spec via(non_neg_integer()) :: {:via, Registry, {atom(), non_neg_integer()}}
  def via(instance_guid) when is_integer(instance_guid) do
    {:via, Registry, {@registry, {:instance, instance_guid}}}
  end

  @doc """
  Returns a via tuple for registering/looking up a boss encounter.
  """
  @spec via_boss(non_neg_integer(), non_neg_integer()) ::
          {:via, Registry, {atom(), {atom(), non_neg_integer(), non_neg_integer()}}}
  def via_boss(instance_guid, boss_id) do
    {:via, Registry, {@registry, {:boss, instance_guid, boss_id}}}
  end

  @doc """
  Looks up an instance process by GUID.
  """
  @spec lookup(non_neg_integer()) :: {:ok, pid()} | :error
  def lookup(instance_guid) do
    case Registry.lookup(@registry, {:instance, instance_guid}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Looks up a boss encounter process.
  """
  @spec lookup_boss(non_neg_integer(), non_neg_integer()) :: {:ok, pid()} | :error
  def lookup_boss(instance_guid, boss_id) do
    case Registry.lookup(@registry, {:boss, instance_guid, boss_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Lists all active instances.
  """
  @spec list_instances() :: [{non_neg_integer(), pid()}]
  def list_instances do
    Registry.select(@registry, [
      {{{:instance, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc """
  Lists all boss encounters for an instance.
  """
  @spec list_bosses(non_neg_integer()) :: [{non_neg_integer(), pid()}]
  def list_bosses(instance_guid) do
    Registry.select(@registry, [
      {{{:boss, instance_guid, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc """
  Counts active instances.
  """
  @spec count_instances() :: non_neg_integer()
  def count_instances do
    length(list_instances())
  end

  @doc """
  Counts instances of a specific type.
  """
  @spec count_instances_by_definition(non_neg_integer()) :: non_neg_integer()
  def count_instances_by_definition(definition_id) do
    list_instances()
    |> Enum.count(fn {_guid, pid} ->
      case GenServer.call(pid, :get_definition_id) do
        ^definition_id -> true
        _ -> false
      end
    end)
  end

  @doc """
  Child spec for starting the registry under a supervisor.
  """
  def child_spec(_opts) do
    %{
      id: @registry,
      start: {Registry, :start_link, [[keys: :unique, name: @registry]]}
    }
  end
end
