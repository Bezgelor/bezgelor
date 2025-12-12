defmodule BezgelorWorld.PvP.WarplotManager do
  @moduledoc """
  Manages warplot ownership, upgrades, and queue.

  Warplots are 40v40 guild-vs-guild fortress battles with
  customizable defenses (plugs).
  """

  use GenServer

  require Logger

  alias BezgelorDb.Warplots

  # War coin costs
  @plug_costs %{
    turret: 500,
    guard_post: 300,
    buff_station: 400,
    heal_station: 400,
    shield_generator: 600,
    teleporter: 350
  }

  @boss_costs %{
    1 => 1000,
    2 => 2000,
    3 => 5000
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Client API

  @doc """
  Get a guild's warplot.
  """
  @spec get_warplot(non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def get_warplot(guild_id) do
    GenServer.call(__MODULE__, {:get_warplot, guild_id})
  end

  @doc """
  Create a new warplot for a guild.
  """
  @spec create_warplot(non_neg_integer(), String.t()) :: {:ok, map()} | {:error, atom()}
  def create_warplot(guild_id, name) do
    GenServer.call(__MODULE__, {:create_warplot, guild_id, name})
  end

  @doc """
  Install a plug in a warplot slot.
  """
  @spec install_plug(non_neg_integer(), non_neg_integer(), atom()) :: {:ok, map()} | {:error, atom()}
  def install_plug(guild_id, slot_id, plug_type) do
    GenServer.call(__MODULE__, {:install_plug, guild_id, slot_id, plug_type})
  end

  @doc """
  Remove a plug from a warplot slot.
  """
  @spec remove_plug(non_neg_integer(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def remove_plug(guild_id, slot_id) do
    GenServer.call(__MODULE__, {:remove_plug, guild_id, slot_id})
  end

  @doc """
  Set the warplot boss.
  """
  @spec set_boss(non_neg_integer(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def set_boss(guild_id, boss_id) do
    GenServer.call(__MODULE__, {:set_boss, guild_id, boss_id})
  end

  @doc """
  Add war coins to a guild's warplot.
  """
  @spec add_war_coins(non_neg_integer(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def add_war_coins(guild_id, amount) do
    GenServer.call(__MODULE__, {:add_war_coins, guild_id, amount})
  end

  @doc """
  Queue a guild for warplot battle.
  """
  @spec queue_for_battle(non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def queue_for_battle(guild_id) do
    GenServer.call(__MODULE__, {:queue_for_battle, guild_id})
  end

  @doc """
  Leave the warplot queue.
  """
  @spec leave_queue(non_neg_integer()) :: :ok | {:error, atom()}
  def leave_queue(guild_id) do
    GenServer.call(__MODULE__, {:leave_queue, guild_id})
  end

  @doc """
  Get queue position for a guild.
  """
  @spec queue_position(non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, :not_in_queue}
  def queue_position(guild_id) do
    GenServer.call(__MODULE__, {:queue_position, guild_id})
  end

  @doc """
  Get plug costs.
  """
  @spec plug_costs() :: map()
  def plug_costs, do: @plug_costs

  @doc """
  Get boss costs.
  """
  @spec boss_costs() :: map()
  def boss_costs, do: @boss_costs

  # Server callbacks

  @impl true
  def init(_opts) do
    Logger.info("WarplotManager started")

    state = %{
      warplot_queue: [],
      active_battles: MapSet.new()
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get_warplot, guild_id}, _from, state) do
    result = Warplots.get_by_guild(guild_id)
    {:reply, result, state}
  end

  def handle_call({:create_warplot, guild_id, name}, _from, state) do
    result = Warplots.create(guild_id, name)
    {:reply, result, state}
  end

  def handle_call({:install_plug, guild_id, slot_id, plug_type}, _from, state) do
    with {:ok, warplot} <- Warplots.get_by_guild(guild_id),
         {:ok, cost} <- get_plug_cost(plug_type),
         :ok <- validate_war_coins(warplot, cost),
         {:ok, updated} <- Warplots.install_plug(warplot.id, slot_id, plug_type, cost) do
      {:reply, {:ok, updated}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:remove_plug, guild_id, slot_id}, _from, state) do
    with {:ok, warplot} <- Warplots.get_by_guild(guild_id),
         {:ok, updated} <- Warplots.remove_plug(warplot.id, slot_id) do
      {:reply, {:ok, updated}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:set_boss, guild_id, boss_id}, _from, state) do
    with {:ok, warplot} <- Warplots.get_by_guild(guild_id),
         {:ok, cost} <- get_boss_cost(boss_id),
         :ok <- validate_war_coins(warplot, cost),
         {:ok, updated} <- Warplots.set_boss(warplot.id, boss_id, cost) do
      {:reply, {:ok, updated}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:add_war_coins, guild_id, amount}, _from, state) do
    with {:ok, warplot} <- Warplots.get_by_guild(guild_id),
         {:ok, updated} <- Warplots.add_war_coins(warplot.id, amount) do
      {:reply, {:ok, updated}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:queue_for_battle, guild_id}, _from, state) do
    with {:ok, warplot} <- Warplots.get_by_guild(guild_id),
         :ok <- validate_not_in_queue(state, guild_id),
         :ok <- validate_warplot_ready(warplot) do
      entry = %{
        guild_id: guild_id,
        warplot: warplot,
        queued_at: System.monotonic_time(:millisecond)
      }

      state = %{state | warplot_queue: state.warplot_queue ++ [entry]}

      # Check if we can start a battle
      state = maybe_start_battle(state)

      {:reply, {:ok, length(state.warplot_queue)}, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:leave_queue, guild_id}, _from, state) do
    queue = Enum.reject(state.warplot_queue, fn e -> e.guild_id == guild_id end)

    if length(queue) < length(state.warplot_queue) do
      {:reply, :ok, %{state | warplot_queue: queue}}
    else
      {:reply, {:error, :not_in_queue}, state}
    end
  end

  def handle_call({:queue_position, guild_id}, _from, state) do
    case Enum.find_index(state.warplot_queue, fn e -> e.guild_id == guild_id end) do
      nil -> {:reply, {:error, :not_in_queue}, state}
      index -> {:reply, {:ok, index + 1}, state}
    end
  end

  @impl true
  def handle_info({:battle_complete, match_id}, state) do
    state = %{state | active_battles: MapSet.delete(state.active_battles, match_id)}
    {:noreply, state}
  end

  # Private functions

  defp get_plug_cost(plug_type) do
    case Map.get(@plug_costs, plug_type) do
      nil -> {:error, :invalid_plug_type}
      cost -> {:ok, cost}
    end
  end

  defp get_boss_cost(boss_id) do
    case Map.get(@boss_costs, boss_id) do
      nil -> {:error, :invalid_boss}
      cost -> {:ok, cost}
    end
  end

  defp validate_war_coins(warplot, cost) do
    if warplot.war_coins >= cost do
      :ok
    else
      {:error, :insufficient_war_coins}
    end
  end

  defp validate_not_in_queue(state, guild_id) do
    if Enum.any?(state.warplot_queue, fn e -> e.guild_id == guild_id end) do
      {:error, :already_in_queue}
    else
      :ok
    end
  end

  defp validate_warplot_ready(warplot) do
    cond do
      is_nil(warplot.boss_id) -> {:error, :no_boss_selected}
      map_size(warplot.plugs || %{}) < 3 -> {:error, :insufficient_defenses}
      true -> :ok
    end
  end

  defp maybe_start_battle(state) do
    if length(state.warplot_queue) >= 2 do
      [team1 | [team2 | remaining]] = state.warplot_queue

      match_id = start_warplot_battle(team1, team2)

      %{
        state
        | warplot_queue: remaining,
          active_battles: MapSet.put(state.active_battles, match_id)
      }
    else
      state
    end
  end

  defp start_warplot_battle(team1, team2) do
    match_id = generate_match_id()

    case BezgelorWorld.PvP.WarplotInstance.start_instance(
           match_id,
           team1.warplot,
           team2.warplot
         ) do
      {:ok, _pid} ->
        Logger.info("Started warplot battle #{match_id}")
        match_id

      {:error, reason} ->
        Logger.error("Failed to start warplot instance: #{inspect(reason)}")
        match_id
    end
  end

  defp generate_match_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
