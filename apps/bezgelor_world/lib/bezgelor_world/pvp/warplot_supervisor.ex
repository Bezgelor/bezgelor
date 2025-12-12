defmodule BezgelorWorld.PvP.WarplotSupervisor do
  @moduledoc """
  Dynamic supervisor for warplot battle instances.

  Each warplot battle runs as a separate GenServer process managed
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
  Get count of active warplot battles.
  """
  @spec active_count() :: non_neg_integer()
  def active_count do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc """
  List all active warplot match IDs.
  """
  @spec list_matches() :: [String.t()]
  def list_matches do
    Registry.select(BezgelorWorld.PvP.WarplotRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end
end
