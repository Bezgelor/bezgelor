defmodule BezgelorWorld.PvP.BattlegroundSupervisor do
  @moduledoc """
  DynamicSupervisor for battleground instances.

  Manages the lifecycle of individual battleground match processes.
  Each match is started when enough players queue and ends when
  the match concludes.
  """

  use DynamicSupervisor

  require Logger

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new battleground instance.
  """
  @spec start_instance(String.t(), non_neg_integer(), list(), list()) ::
          {:ok, pid()} | {:error, term()}
  def start_instance(match_id, battleground_id, exile_team, dominion_team) do
    child_spec = {
      BezgelorWorld.PvP.BattlegroundInstance,
      [
        match_id: match_id,
        battleground_id: battleground_id,
        exile_team: exile_team,
        dominion_team: dominion_team
      ]
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started battleground instance #{match_id}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start battleground instance: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stop a battleground instance.
  """
  @spec stop_instance(String.t()) :: :ok | {:error, :not_found}
  def stop_instance(match_id) do
    case Registry.lookup(BezgelorWorld.PvP.BattlegroundRegistry, match_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Count active battleground instances.
  """
  @spec count_instances() :: non_neg_integer()
  def count_instances do
    DynamicSupervisor.count_children(__MODULE__)[:active] || 0
  end
end
