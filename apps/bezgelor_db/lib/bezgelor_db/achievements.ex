defmodule BezgelorDb.Achievements do
  @moduledoc """
  Achievement management context with PubSub event integration.

  ## Real-Time Achievement Processing

  Achievements are processed via PubSub events. When game events occur
  (kills, quest completions, etc.), events are broadcast and achievement
  criteria are checked in real-time.

  ## Event Types

  - `{:kill, creature_id}` - Creature killed
  - `{:quest_complete, quest_id}` - Quest completed
  - `{:item_collect, item_id, count}` - Items collected
  - `{:level_up, new_level}` - Character leveled up
  - `{:reputation, faction_id, level}` - Reputation level reached
  - `{:achievement, achievement_id}` - Achievement completed (for meta)

  ## Usage

      # Subscribe to achievement events for a character
      Achievements.subscribe(character_id)

      # Broadcast an event
      Achievements.broadcast(character_id, {:kill, creature_id})
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.Achievement

  @pubsub BezgelorCore.PubSub

  # PubSub Functions

  @doc "Subscribe to achievement events for a character."
  @spec subscribe(integer()) :: :ok | {:error, term()}
  def subscribe(character_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(character_id))
  end

  @doc "Unsubscribe from achievement events."
  @spec unsubscribe(integer()) :: :ok
  def unsubscribe(character_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(character_id))
  end

  @doc "Broadcast a game event for achievement processing."
  @spec broadcast(integer(), tuple()) :: :ok | {:error, term()}
  def broadcast(character_id, event) do
    Phoenix.PubSub.broadcast(@pubsub, topic(character_id), {:achievement_event, event})
  end

  defp topic(character_id), do: "achievements:#{character_id}"

  # Achievement Queries

  @doc "Get all achievements for a character."
  @spec get_achievements(integer()) :: [Achievement.t()]
  def get_achievements(character_id) do
    Achievement
    |> where([a], a.character_id == ^character_id)
    |> order_by([a], a.achievement_id)
    |> Repo.all()
  end

  @doc "Get completed achievements for a character."
  @spec get_completed(integer()) :: [Achievement.t()]
  def get_completed(character_id) do
    Achievement
    |> where([a], a.character_id == ^character_id and a.completed == true)
    |> order_by([a], desc: a.completed_at)
    |> Repo.all()
  end

  @doc "Get achievement progress for a specific achievement."
  @spec get_achievement(integer(), integer()) :: Achievement.t() | nil
  def get_achievement(character_id, achievement_id) do
    Repo.get_by(Achievement, character_id: character_id, achievement_id: achievement_id)
  end

  @doc "Check if achievement is completed."
  @spec completed?(integer(), integer()) :: boolean()
  def completed?(character_id, achievement_id) do
    Achievement
    |> where(
      [a],
      a.character_id == ^character_id and a.achievement_id == ^achievement_id and
        a.completed == true
    )
    |> Repo.exists?()
  end

  @doc "Get total achievement points for a character."
  @spec total_points(integer()) :: integer()
  def total_points(character_id) do
    Achievement
    |> where([a], a.character_id == ^character_id and a.completed == true)
    |> Repo.aggregate(:sum, :points_awarded) || 0
  end

  @doc "Count completed achievements."
  @spec completed_count(integer()) :: integer()
  def completed_count(character_id) do
    Achievement
    |> where([a], a.character_id == ^character_id and a.completed == true)
    |> Repo.aggregate(:count)
  end

  # Progress Updates

  @doc """
  Update progress for a simple counter achievement.

  Returns `{:ok, achievement, :completed}` if just completed,
  `{:ok, achievement, :progress}` if progress updated,
  or `{:ok, achievement, :already_complete}` if was already done.
  """
  @spec update_progress(integer(), integer(), integer(), integer()) ::
          {:ok, Achievement.t(), :completed | :progress | :already_complete} | {:error, term()}
  def update_progress(character_id, achievement_id, new_progress, target, points \\ 10) do
    case get_or_create(character_id, achievement_id) do
      {:ok, achievement} ->
        cond do
          achievement.completed ->
            {:ok, achievement, :already_complete}

          new_progress >= target ->
            # Update progress to target before completing
            {:ok, with_progress} =
              achievement
              |> Achievement.progress_changeset(target)
              |> Repo.update()

            complete_achievement(with_progress, points)

          true ->
            {:ok, updated} =
              achievement
              |> Achievement.progress_changeset(new_progress)
              |> Repo.update()

            {:ok, updated, :progress}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc "Increment progress by amount."
  @spec increment_progress(integer(), integer(), integer(), integer()) ::
          {:ok, Achievement.t(), :completed | :progress | :already_complete} | {:error, term()}
  def increment_progress(character_id, achievement_id, amount, target, points \\ 10) do
    case get_or_create(character_id, achievement_id) do
      {:ok, achievement} ->
        new_progress = achievement.progress + amount
        update_progress(character_id, achievement_id, new_progress, target, points)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Update criteria progress for multi-criteria achievements.

  Criteria progress is stored as a map: %{"criteria_1" => true, "criteria_2" => false}
  """
  @spec update_criteria(integer(), integer(), String.t(), boolean(), list(), integer()) ::
          {:ok, Achievement.t(), :completed | :progress | :already_complete} | {:error, term()}
  def update_criteria(
        character_id,
        achievement_id,
        criteria_key,
        value,
        all_criteria,
        points \\ 10
      ) do
    case get_or_create(character_id, achievement_id) do
      {:ok, achievement} ->
        if achievement.completed do
          {:ok, achievement, :already_complete}
        else
          new_criteria = Map.put(achievement.criteria_progress, criteria_key, value)

          # Check if all criteria are met
          all_met =
            Enum.all?(all_criteria, fn key ->
              Map.get(new_criteria, key, false) == true
            end)

          if all_met do
            {:ok, updated} =
              achievement
              |> Achievement.criteria_changeset(new_criteria)
              |> Repo.update()

            complete_achievement(updated, points)
          else
            {:ok, updated} =
              achievement
              |> Achievement.criteria_changeset(new_criteria)
              |> Repo.update()

            {:ok, updated, :progress}
          end
        end

      {:error, _} = err ->
        err
    end
  end

  @doc "Directly complete an achievement (for instant achievements)."
  @spec complete(integer(), integer(), integer()) ::
          {:ok, Achievement.t(), :completed | :already_complete} | {:error, term()}
  def complete(character_id, achievement_id, points \\ 10) do
    case get_or_create(character_id, achievement_id) do
      {:ok, achievement} ->
        if achievement.completed do
          {:ok, achievement, :already_complete}
        else
          complete_achievement(achievement, points)
        end

      {:error, _} = err ->
        err
    end
  end

  # Recent Achievements

  @doc "Get recently completed achievements."
  @spec recent_completions(integer(), integer()) :: [Achievement.t()]
  def recent_completions(character_id, limit \\ 10) do
    Achievement
    |> where([a], a.character_id == ^character_id and a.completed == true)
    |> order_by([a], desc: a.completed_at, desc: a.id)
    |> limit(^limit)
    |> Repo.all()
  end

  # Private Functions

  defp get_or_create(character_id, achievement_id) do
    case get_achievement(character_id, achievement_id) do
      nil ->
        %Achievement{}
        |> Achievement.changeset(%{
          character_id: character_id,
          achievement_id: achievement_id
        })
        |> Repo.insert()

      achievement ->
        {:ok, achievement}
    end
  end

  defp complete_achievement(achievement, points) do
    {:ok, updated} =
      achievement
      |> Achievement.complete_changeset(points)
      |> Repo.update()

    # Broadcast completion for meta achievements
    broadcast(achievement.character_id, {:achievement, achievement.achievement_id})

    {:ok, updated, :completed}
  end
end
