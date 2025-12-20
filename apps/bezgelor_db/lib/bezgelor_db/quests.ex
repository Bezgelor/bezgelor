defmodule BezgelorDb.Quests do
  @moduledoc """
  Quest management context.

  ## Hybrid Storage

  Active quests use JSON for flexible objective progress,
  while completed quests are stored in normalized history
  for efficient queries.

  ## Quest Lifecycle

  1. Accept quest → creates Quest record with :accepted state
  2. Update progress → modifies JSON progress field
  3. Complete objectives → state changes to :complete
  4. Turn in quest → creates QuestHistory, deletes Quest
  """

  import Ecto.Query
  alias BezgelorDb.Repo
  alias BezgelorDb.Schema.{Quest, QuestHistory}

  @max_active_quests 25

  # Active Quest Management

  @doc "Get all active quests for a character."
  @spec get_active_quests(integer()) :: [Quest.t()]
  def get_active_quests(character_id) do
    Quest
    |> where([q], q.character_id == ^character_id)
    |> where([q], q.state in [:accepted, :complete])
    |> order_by([q], desc: q.accepted_at)
    |> Repo.all()
  end

  @doc "Get a specific active quest."
  @spec get_quest(integer(), integer()) :: Quest.t() | nil
  def get_quest(character_id, quest_id) do
    Repo.get_by(Quest, character_id: character_id, quest_id: quest_id)
  end

  @doc "Check if character has an active quest."
  @spec has_quest?(integer(), integer()) :: boolean()
  def has_quest?(character_id, quest_id) do
    Quest
    |> where([q], q.character_id == ^character_id and q.quest_id == ^quest_id)
    |> Repo.exists?()
  end

  @doc "Count active quests for a character."
  @spec count_active_quests(integer()) :: integer()
  def count_active_quests(character_id) do
    Quest
    |> where([q], q.character_id == ^character_id)
    |> where([q], q.state in [:accepted, :complete])
    |> Repo.aggregate(:count)
  end

  @doc """
  Accept a new quest.

  ## Options

  - `:progress` - Initial progress map
  - `:expires_at` - Quest expiration time (for timed quests)
  """
  @spec accept_quest(integer(), integer(), keyword()) ::
          {:ok, Quest.t()} | {:error, :quest_log_full | :already_have_quest | term()}
  def accept_quest(character_id, quest_id, opts \\ []) do
    cond do
      has_quest?(character_id, quest_id) ->
        {:error, :already_have_quest}

      count_active_quests(character_id) >= @max_active_quests ->
        {:error, :quest_log_full}

      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        attrs = %{
          character_id: character_id,
          quest_id: quest_id,
          state: :accepted,
          progress: Keyword.get(opts, :progress, %{}),
          accepted_at: now,
          expires_at: Keyword.get(opts, :expires_at)
        }

        %Quest{}
        |> Quest.changeset(attrs)
        |> Repo.insert()
    end
  end

  @doc "Update quest progress."
  @spec update_progress(Quest.t(), map()) :: {:ok, Quest.t()} | {:error, term()}
  def update_progress(quest, progress) do
    quest
    |> Quest.progress_changeset(progress)
    |> Repo.update()
  end

  @doc "Update a specific objective's progress."
  @spec update_objective(Quest.t(), integer(), integer()) :: {:ok, Quest.t()} | {:error, term()}
  def update_objective(quest, objective_index, current_value) do
    objectives = get_in(quest.progress, ["objectives"]) || []

    updated_objectives =
      Enum.map(objectives, fn obj ->
        if obj["index"] == objective_index do
          Map.put(obj, "current", current_value)
        else
          obj
        end
      end)

    new_progress = put_in(quest.progress, ["objectives"], updated_objectives)
    update_progress(quest, new_progress)
  end

  @doc "Increment an objective's progress by amount."
  @spec increment_objective(Quest.t(), integer(), integer()) ::
          {:ok, Quest.t()} | {:error, term()}
  def increment_objective(quest, objective_index, amount \\ 1) do
    objectives = get_in(quest.progress, ["objectives"]) || []

    case Enum.find(objectives, &(&1["index"] == objective_index)) do
      nil ->
        {:error, :objective_not_found}

      objective ->
        current = objective["current"] || 0
        update_objective(quest, objective_index, current + amount)
    end
  end

  @doc "Mark quest as complete (all objectives done)."
  @spec mark_complete(Quest.t()) :: {:ok, Quest.t()} | {:error, term()}
  def mark_complete(quest) do
    quest
    |> Quest.complete_changeset()
    |> Repo.update()
  end

  @doc "Mark quest as failed."
  @spec fail_quest(Quest.t()) :: {:ok, Quest.t()} | {:error, term()}
  def fail_quest(quest) do
    quest
    |> Quest.fail_changeset()
    |> Repo.update()
  end

  @doc "Abandon an active quest."
  @spec abandon_quest(integer(), integer()) :: {:ok, Quest.t()} | {:error, :not_found}
  def abandon_quest(character_id, quest_id) do
    case get_quest(character_id, quest_id) do
      nil -> {:error, :not_found}
      quest -> Repo.delete(quest)
    end
  end

  @doc """
  Turn in a completed quest.

  Moves quest to history and deletes active quest record.
  Returns the history entry.
  """
  @spec turn_in_quest(integer(), integer()) ::
          {:ok, QuestHistory.t()} | {:error, :not_found | :not_complete | term()}
  def turn_in_quest(character_id, quest_id) do
    case get_quest(character_id, quest_id) do
      nil ->
        {:error, :not_found}

      %{state: state} when state != :complete ->
        {:error, :not_complete}

      quest ->
        Repo.transaction(fn ->
          # Add to history
          {:ok, history} = add_to_history(character_id, quest_id)

          # Delete active quest
          {:ok, _} = Repo.delete(quest)

          history
        end)
    end
  end

  # Quest History

  @doc "Get quest history for a character."
  @spec get_history(integer()) :: [QuestHistory.t()]
  def get_history(character_id) do
    QuestHistory
    |> where([h], h.character_id == ^character_id)
    |> order_by([h], desc: h.completed_at)
    |> Repo.all()
  end

  @doc "Check if character has completed a quest."
  @spec has_completed?(integer(), integer()) :: boolean()
  def has_completed?(character_id, quest_id) do
    QuestHistory
    |> where([h], h.character_id == ^character_id and h.quest_id == ^quest_id)
    |> Repo.exists?()
  end

  @doc "Get completion count for a quest."
  @spec completion_count(integer(), integer()) :: integer()
  def completion_count(character_id, quest_id) do
    case Repo.get_by(QuestHistory, character_id: character_id, quest_id: quest_id) do
      nil -> 0
      history -> history.completion_count
    end
  end

  @doc "Check if repeatable quest is available (based on reset time)."
  @spec repeatable_available?(integer(), integer(), DateTime.t()) :: boolean()
  def repeatable_available?(character_id, quest_id, reset_time) do
    case Repo.get_by(QuestHistory, character_id: character_id, quest_id: quest_id) do
      nil ->
        true

      history ->
        case history.last_completion do
          nil -> true
          last -> DateTime.compare(last, reset_time) == :lt
        end
    end
  end

  # Objective Helpers

  @doc "Check if all objectives are complete."
  @spec all_objectives_complete?(Quest.t()) :: boolean()
  def all_objectives_complete?(quest) do
    objectives = get_in(quest.progress, ["objectives"]) || []

    Enum.all?(objectives, fn obj ->
      current = obj["current"] || 0
      target = obj["target"] || 1
      current >= target
    end)
  end

  @doc "Get progress for a specific objective."
  @spec get_objective_progress(Quest.t(), integer()) :: {integer(), integer()} | nil
  def get_objective_progress(quest, objective_index) do
    objectives = get_in(quest.progress, ["objectives"]) || []

    case Enum.find(objectives, &(&1["index"] == objective_index)) do
      nil -> nil
      obj -> {obj["current"] || 0, obj["target"] || 1}
    end
  end

  @doc "Initialize quest progress with objectives."
  @spec init_progress(list()) :: map()
  def init_progress(objectives) do
    %{
      "objectives" =>
        Enum.with_index(objectives)
        |> Enum.map(fn {obj, idx} ->
          %{
            "index" => idx,
            "current" => 0,
            "target" => obj[:target] || obj["target"] || 1,
            "type" => to_string(obj[:type] || obj["type"] || "unknown")
          }
        end),
      "flags" => %{}
    }
  end

  @doc "Maximum active quests allowed."
  @spec max_active_quests() :: integer()
  def max_active_quests, do: @max_active_quests

  # Private

  defp add_to_history(character_id, quest_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(QuestHistory, character_id: character_id, quest_id: quest_id) do
      nil ->
        %QuestHistory{}
        |> QuestHistory.changeset(%{
          character_id: character_id,
          quest_id: quest_id,
          completed_at: now,
          last_completion: now
        })
        |> Repo.insert()

      history ->
        # Repeatable quest - increment count
        history
        |> QuestHistory.increment_changeset()
        |> Repo.update()
    end
  end
end
