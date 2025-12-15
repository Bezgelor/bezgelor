defmodule BezgelorWorld.Quest.QuestCache do
  @moduledoc """
  Quest caching utilities for session-based quest management.

  ## Overview

  Handles loading quest data from the database and converting between
  the database schema format (Quest) and the session map format used
  for in-memory quest tracking.

  ## Session Format

  Quests are stored in session_data as:

      %{
        active_quests: %{
          quest_id => %{
            quest_id: 123,
            state: :accepted | :complete,
            accepted_at: ~U[2025-12-12 10:00:00Z],
            dirty: false,
            objectives: [
              %{index: 0, type: 2, data: 12345, current: 3, target: 10}
            ]
          }
        },
        completed_quest_ids: MapSet.new([1, 2, 3]),
        quest_dirty: false
      }

  ## Usage

      # On login
      {:ok, quests, completed_ids} = QuestCache.load_quests_for_character(character_id)
      session_data = %{session_data | active_quests: quests, completed_quest_ids: completed_ids}

      # Before logout
      dirty_quests = QuestCache.get_dirty_quests(session_data.active_quests)
      Enum.each(dirty_quests, &QuestPersistence.persist/1)
  """

  alias BezgelorDb.Quests
  alias BezgelorDb.Schema.Quest
  alias BezgelorData.Store

  require Logger

  @type session_quest :: %{
          quest_id: non_neg_integer(),
          state: :accepted | :complete,
          accepted_at: DateTime.t(),
          dirty: boolean(),
          objectives: [objective()]
        }

  @type objective :: %{
          index: non_neg_integer(),
          type: non_neg_integer(),
          data: non_neg_integer(),
          current: non_neg_integer(),
          target: non_neg_integer()
        }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Load all quests for a character from the database.

  Returns a tuple with:
  - Map of active quests in session format (keyed by quest_id)
  - MapSet of completed quest IDs

  ## Examples

      {:ok, active_quests, completed_ids} = QuestCache.load_quests_for_character(123)
  """
  @spec load_quests_for_character(non_neg_integer()) ::
          {:ok, %{non_neg_integer() => session_quest()}, MapSet.t()}
  def load_quests_for_character(character_id) do
    # Load active quests from DB
    active_db_quests = Quests.get_active_quests(character_id)

    # Convert each to session format
    active_quests =
      active_db_quests
      |> Enum.map(&to_session_format/1)
      |> Enum.filter(&(&1 != nil))
      |> Map.new(fn quest -> {quest.quest_id, quest} end)

    # Load completed quest IDs from history
    completed_ids =
      Quests.get_history(character_id)
      |> Enum.map(& &1.quest_id)
      |> MapSet.new()

    Logger.debug(
      "Loaded #{map_size(active_quests)} active quests, #{MapSet.size(completed_ids)} completed for character #{character_id}"
    )

    {:ok, active_quests, completed_ids}
  end

  @doc """
  Convert a Quest database schema to session format.

  Enriches the quest with objective definitions from static data.

  ## Returns

  A session quest map, or nil if quest data is invalid.
  """
  @spec to_session_format(Quest.t()) :: session_quest() | nil
  def to_session_format(%Quest{} = quest) do
    case Store.get_quest_with_objectives(quest.quest_id) do
      {:ok, quest_def} ->
        build_session_quest(quest, quest_def)

      :error ->
        Logger.warning("Quest #{quest.quest_id} not found in static data, skipping")
        nil
    end
  end

  @doc """
  Convert a session quest back to database format for persistence.

  ## Returns

  A map suitable for updating the Quest schema in the database.
  """
  @spec from_session_format(session_quest()) :: map()
  def from_session_format(session_quest) do
    objectives_json =
      Enum.map(session_quest.objectives, fn obj ->
        %{
          "index" => obj.index,
          "current" => obj.current,
          "target" => obj.target,
          "type" => to_string(obj.type)
        }
      end)

    %{
      quest_id: session_quest.quest_id,
      state: session_quest.state,
      progress: %{"objectives" => objectives_json, "flags" => %{}}
    }
  end

  @doc """
  Mark a quest as dirty (needing persistence).

  ## Returns

  Updated active_quests map with the quest marked dirty.
  """
  @spec mark_dirty(%{non_neg_integer() => session_quest()}, non_neg_integer()) ::
          %{non_neg_integer() => session_quest()}
  def mark_dirty(active_quests, quest_id) do
    case Map.get(active_quests, quest_id) do
      nil ->
        active_quests

      quest ->
        Map.put(active_quests, quest_id, %{quest | dirty: true})
    end
  end

  @doc """
  Get all quests that need to be persisted.

  ## Returns

  List of session quests with dirty: true.
  """
  @spec get_dirty_quests(%{non_neg_integer() => session_quest()}) :: [session_quest()]
  def get_dirty_quests(active_quests) do
    active_quests
    |> Map.values()
    |> Enum.filter(& &1.dirty)
  end

  @doc """
  Clear dirty flag on all quests (after successful persistence).

  ## Parameters

  - `active_quests` - The active quests map
  - `quest_ids` - Optional list of quest IDs to clear. If nil, clears all.

  ## Returns

  Updated active_quests map with dirty flags cleared.
  """
  @spec clear_dirty_flags(%{non_neg_integer() => session_quest()}, [non_neg_integer()] | nil) ::
          %{non_neg_integer() => session_quest()}
  def clear_dirty_flags(active_quests, quest_ids \\ nil)

  def clear_dirty_flags(active_quests, nil) do
    # Clear all dirty flags (legacy behavior)
    Map.new(active_quests, fn {quest_id, quest} ->
      {quest_id, %{quest | dirty: false}}
    end)
  end

  def clear_dirty_flags(active_quests, quest_ids) when is_list(quest_ids) do
    # Only clear dirty flags for specified quest IDs
    quest_id_set = MapSet.new(quest_ids)

    Map.new(active_quests, fn {quest_id, quest} ->
      if MapSet.member?(quest_id_set, quest_id) do
        {quest_id, %{quest | dirty: false}}
      else
        {quest_id, quest}
      end
    end)
  end

  @doc """
  Create a new session quest from static data when accepting a quest.

  ## Returns

  A session quest map with objectives initialized to 0 progress.
  """
  @spec create_session_quest(non_neg_integer()) :: {:ok, session_quest()} | {:error, :not_found}
  def create_session_quest(quest_id) do
    case Store.get_quest_with_objectives(quest_id) do
      {:ok, quest_def} ->
        objectives =
          quest_def.objectives
          |> Enum.with_index()
          |> Enum.map(fn {obj_def, idx} ->
            %{
              index: idx,
              type: obj_def[:type] || 0,
              data: obj_def[:data] || 0,
              current: 0,
              target: obj_def[:count] || 1
            }
          end)

        session_quest = %{
          quest_id: quest_id,
          state: :accepted,
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          dirty: true,
          objectives: objectives
        }

        {:ok, session_quest}

      :error ->
        {:error, :not_found}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_session_quest(%Quest{} = db_quest, quest_def) do
    # Get objectives from DB progress if available, otherwise init from static
    db_objectives = get_in(db_quest.progress, ["objectives"]) || []

    objectives =
      quest_def.objectives
      |> Enum.with_index()
      |> Enum.map(fn {obj_def, idx} ->
        # Find matching DB progress for this objective
        db_obj = Enum.find(db_objectives, fn o -> o["index"] == idx end)

        %{
          index: idx,
          type: obj_def[:type] || 0,
          data: obj_def[:data] || 0,
          current: (db_obj && db_obj["current"]) || 0,
          target: obj_def[:count] || 1
        }
      end)

    %{
      quest_id: db_quest.quest_id,
      state: db_quest.state,
      accepted_at: db_quest.accepted_at,
      dirty: false,
      objectives: objectives
    }
  end
end
