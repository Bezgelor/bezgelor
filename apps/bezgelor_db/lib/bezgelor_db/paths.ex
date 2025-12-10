defmodule BezgelorDb.Paths do
  @moduledoc """
  Path progression and mission management.

  ## Path Types

  - `0` - Soldier - Combat missions
  - `1` - Settler - Building/depot missions
  - `2` - Scientist - Scanning/lore missions
  - `3` - Explorer - Exploration/jumping puzzles

  ## Leveling

  Path XP is earned from path missions and some world activities.
  Each level unlocks new abilities and path features.
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Path, PathMission}

  # XP required per level (simplified - real game has different curve)
  @xp_per_level 1000
  @max_level 30

  # Path Queries

  @doc "Get character's path or nil if not initialized."
  @spec get_path(integer()) :: Path.t() | nil
  def get_path(character_id) do
    Repo.get_by(Path, character_id: character_id)
  end

  @doc "Initialize path for a character."
  @spec initialize_path(integer(), integer()) :: {:ok, Path.t()} | {:error, term()}
  def initialize_path(character_id, path_type) do
    %Path{}
    |> Path.changeset(%{character_id: character_id, path_type: path_type})
    |> Repo.insert()
  end

  @doc "Get path level and XP."
  @spec get_progress(integer()) :: {integer(), integer()} | nil
  def get_progress(character_id) do
    case get_path(character_id) do
      nil -> nil
      path -> {path.path_level, path.path_xp}
    end
  end

  @doc "Award path XP, handling level ups."
  @spec award_xp(integer(), integer()) ::
          {:ok, Path.t(), :xp_gained | :level_up} | {:error, term()}
  def award_xp(character_id, xp_amount) when xp_amount > 0 do
    case get_path(character_id) do
      nil ->
        {:error, :path_not_initialized}

      path ->
        new_xp = path.path_xp + xp_amount
        {new_level, remaining_xp} = calculate_level(path.path_level, new_xp)

        result_type = if new_level > path.path_level, do: :level_up, else: :xp_gained

        {:ok, updated} =
          path
          |> Path.xp_changeset(remaining_xp, new_level)
          |> Repo.update()

        {:ok, updated, result_type}
    end
  end

  @doc "Unlock a path ability."
  @spec unlock_ability(integer(), integer()) :: {:ok, Path.t()} | {:error, term()}
  def unlock_ability(character_id, ability_id) do
    case get_path(character_id) do
      nil ->
        {:error, :path_not_initialized}

      path ->
        if ability_id in path.unlocked_abilities do
          {:ok, path}
        else
          path
          |> Path.unlock_ability_changeset(ability_id)
          |> Repo.update()
        end
    end
  end

  @doc "Check if ability is unlocked."
  @spec ability_unlocked?(integer(), integer()) :: boolean()
  def ability_unlocked?(character_id, ability_id) do
    case get_path(character_id) do
      nil -> false
      path -> ability_id in path.unlocked_abilities
    end
  end

  # Mission Queries

  @doc "Get all active missions for a character."
  @spec get_active_missions(integer()) :: [PathMission.t()]
  def get_active_missions(character_id) do
    PathMission
    |> where([m], m.character_id == ^character_id and m.state == :active)
    |> order_by([m], m.mission_id)
    |> Repo.all()
  end

  @doc "Get a specific mission."
  @spec get_mission(integer(), integer()) :: PathMission.t() | nil
  def get_mission(character_id, mission_id) do
    Repo.get_by(PathMission, character_id: character_id, mission_id: mission_id)
  end

  @doc "Get completed missions count."
  @spec completed_mission_count(integer()) :: integer()
  def completed_mission_count(character_id) do
    PathMission
    |> where([m], m.character_id == ^character_id and m.state == :completed)
    |> Repo.aggregate(:count)
  end

  # Mission Operations

  @doc "Accept a path mission."
  @spec accept_mission(integer(), integer()) :: {:ok, PathMission.t()} | {:error, term()}
  def accept_mission(character_id, mission_id) do
    case get_mission(character_id, mission_id) do
      nil ->
        %PathMission{}
        |> PathMission.changeset(%{
          character_id: character_id,
          mission_id: mission_id,
          state: :active,
          progress: %{}
        })
        |> Repo.insert()

      existing ->
        {:error, {:already_exists, existing.state}}
    end
  end

  @doc "Update mission progress."
  @spec update_progress(integer(), integer(), map()) ::
          {:ok, PathMission.t()} | {:error, term()}
  def update_progress(character_id, mission_id, progress) do
    case get_mission(character_id, mission_id) do
      nil ->
        {:error, :mission_not_found}

      %{state: :active} = mission ->
        new_progress = Map.merge(mission.progress, progress)

        mission
        |> PathMission.progress_changeset(new_progress)
        |> Repo.update()

      mission ->
        {:error, {:invalid_state, mission.state}}
    end
  end

  @doc "Increment a counter in mission progress."
  @spec increment_counter(integer(), integer(), String.t(), integer(), integer()) ::
          {:ok, PathMission.t(), :progress | :target_reached} | {:error, term()}
  def increment_counter(character_id, mission_id, counter_key, amount \\ 1, target \\ nil) do
    case get_mission(character_id, mission_id) do
      nil ->
        {:error, :mission_not_found}

      %{state: :active} = mission ->
        current = Map.get(mission.progress, counter_key, 0)
        new_value = current + amount

        new_progress = Map.put(mission.progress, counter_key, new_value)

        {:ok, updated} =
          mission
          |> PathMission.progress_changeset(new_progress)
          |> Repo.update()

        result = if target && new_value >= target, do: :target_reached, else: :progress
        {:ok, updated, result}

      mission ->
        {:error, {:invalid_state, mission.state}}
    end
  end

  @doc "Complete a mission."
  @spec complete_mission(integer(), integer()) :: {:ok, PathMission.t()} | {:error, term()}
  def complete_mission(character_id, mission_id) do
    case get_mission(character_id, mission_id) do
      nil ->
        {:error, :mission_not_found}

      %{state: :active} = mission ->
        mission
        |> PathMission.complete_changeset()
        |> Repo.update()

      %{state: :completed} = mission ->
        {:ok, mission}

      mission ->
        {:error, {:invalid_state, mission.state}}
    end
  end

  @doc "Fail a mission."
  @spec fail_mission(integer(), integer()) :: {:ok, PathMission.t()} | {:error, term()}
  def fail_mission(character_id, mission_id) do
    case get_mission(character_id, mission_id) do
      nil ->
        {:error, :mission_not_found}

      %{state: :active} = mission ->
        mission
        |> PathMission.fail_changeset()
        |> Repo.update()

      mission ->
        {:error, {:invalid_state, mission.state}}
    end
  end

  @doc "Abandon a mission (delete it so it can be restarted)."
  @spec abandon_mission(integer(), integer()) :: :ok | {:error, term()}
  def abandon_mission(character_id, mission_id) do
    case get_mission(character_id, mission_id) do
      nil ->
        :ok

      %{state: :completed} ->
        {:error, :cannot_abandon_completed}

      mission ->
        Repo.delete(mission)
        :ok
    end
  end

  # Private Functions

  defp calculate_level(current_level, xp) when current_level >= @max_level do
    # At max level, just accumulate XP
    {@max_level, xp}
  end

  defp calculate_level(current_level, xp) do
    xp_needed = xp_for_level(current_level + 1)

    if xp >= xp_needed do
      # Level up and check for more
      calculate_level(current_level + 1, xp - xp_needed)
    else
      {current_level, xp}
    end
  end

  defp xp_for_level(level), do: level * @xp_per_level
end
