defmodule BezgelorWorld.PvP.ArenaSupervisor do
  @moduledoc """
  Dynamic supervisor for arena instances.

  Each arena match runs as a separate GenServer process managed
  by this supervisor.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Get count of active arena matches.
  """
  @spec active_count() :: non_neg_integer()
  def active_count do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc """
  List all active arena match IDs.
  """
  @spec list_matches() :: [String.t()]
  def list_matches do
    Registry.select(BezgelorWorld.PvP.ArenaRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end
end
