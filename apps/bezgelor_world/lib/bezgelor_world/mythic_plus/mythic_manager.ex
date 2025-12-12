defmodule BezgelorWorld.MythicPlus.MythicManager do
  @moduledoc """
  Manages Mythic+ keystones and weekly affix rotation.

  Handles:
  - Keystone activation and validation
  - Affix rotation on weekly reset
  - Score calculation for completed runs
  - Leaderboard queries
  - Keystone upgrades/depletions
  """

  use GenServer
  require Logger

  alias BezgelorDb.Instances
  alias BezgelorDb.Schema.MythicKeystone

  @current_season 1

  # Client API

  @doc """
  Starts the mythic manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current weekly affixes.
  """
  @spec get_weekly_affixes() :: map()
  def get_weekly_affixes do
    GenServer.call(__MODULE__, :get_weekly_affixes)
  end

  @doc """
  Activate a keystone for a dungeon run.

  Returns activation data including affixes and time limit.
  """
  @spec activate_keystone(integer(), integer()) ::
          {:ok, map()} | {:error, atom()}
  def activate_keystone(character_id, keystone_id) do
    GenServer.call(__MODULE__, {:activate_keystone, character_id, keystone_id})
  end

  @doc """
  Record a completed mythic+ run.
  """
  @spec complete_run(map()) :: {:ok, term()} | {:error, term()}
  def complete_run(run_data) do
    GenServer.call(__MODULE__, {:complete_run, run_data})
  end

  @doc """
  Deplete a character's keystone after a failed run.
  """
  @spec deplete_keystone(integer()) :: {:ok, term()} | {:error, term()}
  def deplete_keystone(character_id) do
    GenServer.call(__MODULE__, {:deplete_keystone, character_id})
  end

  @doc """
  Get a player's weekly best runs.
  """
  @spec get_weekly_best(integer()) :: [term()]
  def get_weekly_best(character_id) do
    GenServer.call(__MODULE__, {:get_weekly_best, character_id})
  end

  @doc """
  Get leaderboard for a dungeon at a specific level.
  """
  @spec get_leaderboard(integer(), integer(), integer()) :: [term()]
  def get_leaderboard(instance_id, level, limit \\ 100) do
    GenServer.call(__MODULE__, {:get_leaderboard, instance_id, level, limit})
  end

  @doc """
  Grant a new keystone to a character.
  """
  @spec grant_keystone(integer(), integer(), integer()) :: {:ok, term()} | {:error, term()}
  def grant_keystone(character_id, instance_id, level) do
    GenServer.call(__MODULE__, {:grant_keystone, character_id, instance_id, level})
  end

  @doc """
  Get the current season number.
  """
  @spec get_current_season() :: integer()
  def get_current_season do
    @current_season
  end

  @doc """
  Get affixes for a specific keystone level.
  """
  @spec get_affixes_for_level(integer()) :: [atom()]
  def get_affixes_for_level(level) do
    weekly = get_weekly_affixes()
    build_affix_list(level, weekly)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    affixes = calculate_weekly_affixes()
    current_week = get_current_week()

    state = %{
      season: @current_season,
      weekly_affixes: affixes,
      affix_week: current_week
    }

    Logger.info("MythicManager started - Season #{@current_season}, Week #{current_week}, Affixes: #{inspect(affixes)}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_weekly_affixes, _from, state) do
    # Check if week changed
    current_week = get_current_week()

    state =
      if current_week != state.affix_week do
        new_affixes = calculate_weekly_affixes()
        Logger.info("Weekly affix rotation: #{inspect(new_affixes)}")
        %{state | weekly_affixes: new_affixes, affix_week: current_week}
      else
        state
      end

    {:reply, state.weekly_affixes, state}
  end

  def handle_call({:activate_keystone, character_id, keystone_id}, _from, state) do
    result = do_activate_keystone(character_id, keystone_id, state.weekly_affixes)
    {:reply, result, state}
  end

  def handle_call({:complete_run, run_data}, _from, state) do
    result = do_complete_run(run_data, state.season)
    {:reply, result, state}
  end

  def handle_call({:deplete_keystone, character_id}, _from, state) do
    result = Instances.deplete_keystone(character_id)
    {:reply, result, state}
  end

  def handle_call({:get_weekly_best, character_id}, _from, state) do
    runs = Instances.get_player_best_runs(character_id, state.season, 10)
    {:reply, runs, state}
  end

  def handle_call({:get_leaderboard, instance_id, level, limit}, _from, state) do
    runs = Instances.get_season_leaderboard(instance_id, level, state.season, limit)
    {:reply, runs, state}
  end

  def handle_call({:grant_keystone, character_id, instance_id, level}, _from, state) do
    affixes = Enum.map(build_affix_list(level, state.weekly_affixes), &Atom.to_string/1)
    result = Instances.grant_keystone(character_id, instance_id, level, affixes)
    {:reply, result, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp calculate_weekly_affixes do
    week = get_current_week()
    config = Application.get_env(:bezgelor_world, :mythic_plus, %{})
    affix_config = config[:affixes] || %{}

    # Default affix rotations
    minor_affixes = affix_config[:minor] || [:fortified, :tyrannical]
    major_affixes = affix_config[:major] || [:bolstering, :sanguine, :bursting, :raging]
    seasonal_affixes = affix_config[:seasonal] || [:primal, :encrypted, :awakened]

    minor = Enum.at(minor_affixes, rem(week, length(minor_affixes)))
    major = Enum.at(major_affixes, rem(week, length(major_affixes)))
    seasonal = Enum.at(seasonal_affixes, rem(week, length(seasonal_affixes)))

    %{minor: minor, major: major, seasonal: seasonal}
  end

  defp get_current_week do
    # Week number since a reference date
    div(Date.diff(Date.utc_today(), ~D[2025-01-01]), 7)
  end

  defp do_activate_keystone(character_id, keystone_id, weekly_affixes) do
    case BezgelorDb.Repo.get(MythicKeystone, keystone_id) do
      nil ->
        {:error, :keystone_not_found}

      %MythicKeystone{character_id: ^character_id, depleted: false} = keystone ->
        {:ok,
         %{
           keystone: keystone,
           affixes: build_affix_list(keystone.level, weekly_affixes),
           time_limit: get_time_limit(keystone.instance_definition_id),
           scaling: calculate_scaling(keystone.level)
         }}

      %MythicKeystone{character_id: ^character_id, depleted: true} ->
        {:error, :keystone_depleted}

      %MythicKeystone{} ->
        {:error, :not_owner}
    end
  end

  defp build_affix_list(level, weekly) do
    cond do
      level >= 10 -> [weekly.minor, weekly.major, weekly.seasonal]
      level >= 5 -> [weekly.minor, weekly.major]
      level >= 2 -> [weekly.minor]
      true -> []
    end
  end

  defp get_time_limit(instance_id) do
    config = Application.get_env(:bezgelor_world, :mythic_plus, %{})
    time_limits = config[:time_limits] || %{}

    # Default 30 minutes if not configured
    Map.get(time_limits, instance_id, 30 * 60)
  end

  defp calculate_scaling(level) do
    # Exponential scaling for health and damage
    base_multiplier = 1.0 + (level * 0.1)
    health_multiplier = :math.pow(base_multiplier, 1.2)
    damage_multiplier = :math.pow(base_multiplier, 1.1)

    %{
      health: health_multiplier,
      damage: damage_multiplier,
      level: level
    }
  end

  defp do_complete_run(run_data, season) do
    run_data_with_season = Map.put(run_data, :season, season)

    # Calculate keystone rating based on completion
    rating = calculate_run_rating(run_data)
    run_data_with_rating = Map.put(run_data_with_season, :rating, rating)

    case Instances.record_mythic_run(run_data_with_rating) do
      {:ok, run} ->
        # Handle keystone upgrade/deplete based on timer
        handle_keystone_result(run_data)
        {:ok, run}

      error ->
        error
    end
  end

  defp calculate_run_rating(run_data) do
    base_rating = run_data[:level] * 10
    time_bonus = if run_data[:timed], do: 5, else: 0

    # Bonus for beating timer by significant margins
    plus_bonus =
      cond do
        run_data[:plus_three] -> 15
        run_data[:plus_two] -> 10
        true -> 0
      end

    base_rating + time_bonus + plus_bonus
  end

  defp handle_keystone_result(run_data) do
    character_id = run_data[:leader_id] || hd(run_data[:member_ids] || [0])

    cond do
      run_data[:plus_three] ->
        # Upgrade by 3 levels
        Instances.upgrade_keystone(character_id, 3)

      run_data[:plus_two] ->
        # Upgrade by 2 levels
        Instances.upgrade_keystone(character_id, 2)

      run_data[:timed] ->
        # Upgrade by 1 level
        Instances.upgrade_keystone(character_id, 1)

      true ->
        # Failed timer - deplete
        Instances.deplete_keystone(character_id)
    end
  end
end
