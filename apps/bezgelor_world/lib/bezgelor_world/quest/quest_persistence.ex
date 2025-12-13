defmodule BezgelorWorld.Quest.QuestPersistence do
  @moduledoc """
  Quest persistence utilities for saving session quest state to database.

  ## Overview

  Handles persisting dirty quests from session_data to the database.
  Called:
  - Periodically (every 30 seconds) via Connection timer
  - On logout/disconnect
  - After significant quest state changes

  ## Usage

      # Persist all dirty quests for a character
      {:ok, count} = QuestPersistence.persist_dirty_quests(character_id, session_data)

      # Persist a single quest
      :ok = QuestPersistence.persist_quest(character_id, session_quest)
  """

  alias BezgelorDb.Quests
  alias BezgelorWorld.Quest.QuestCache

  require Logger

  @doc """
  Persist all dirty quests from session data to the database.

  Returns the number of quests persisted and updated session_data with
  dirty flags cleared.

  ## Parameters

  - `character_id` - The character whose quests to persist
  - `session_data` - The session data containing active_quests

  ## Returns

  `{:ok, count, updated_session_data}` on success
  `{:error, reason}` on failure
  """
  @spec persist_dirty_quests(non_neg_integer(), map()) ::
          {:ok, non_neg_integer(), map()} | {:error, term()}
  def persist_dirty_quests(character_id, session_data) do
    active_quests = session_data[:active_quests] || %{}
    dirty_quests = QuestCache.get_dirty_quests(active_quests)

    if dirty_quests == [] do
      {:ok, 0, session_data}
    else
      Logger.debug("Persisting #{length(dirty_quests)} dirty quests for character #{character_id}")

      # Persist each dirty quest
      results =
        Enum.map(dirty_quests, fn quest ->
          persist_quest(character_id, quest)
        end)

      # Count successes
      success_count = Enum.count(results, &(&1 == :ok))
      failure_count = length(results) - success_count

      if failure_count > 0 do
        Logger.warning("Failed to persist #{failure_count} quests for character #{character_id}")
      end

      # Clear dirty flags on successfully persisted quests
      updated_active_quests = QuestCache.clear_dirty_flags(active_quests)
      updated_session_data = Map.put(session_data, :active_quests, updated_active_quests)

      {:ok, success_count, updated_session_data}
    end
  end

  @doc """
  Persist a single quest to the database.

  Updates the quest's progress in the database based on session state.

  ## Parameters

  - `character_id` - The character who owns the quest
  - `session_quest` - The session quest to persist

  ## Returns

  `:ok` on success
  `{:error, reason}` on failure
  """
  @spec persist_quest(non_neg_integer(), QuestCache.session_quest()) :: :ok | {:error, term()}
  def persist_quest(character_id, session_quest) do
    quest_id = session_quest.quest_id

    case Quests.get_quest(character_id, quest_id) do
      nil ->
        # Quest not in DB yet - might be newly accepted
        Logger.debug("Quest #{quest_id} not found in DB for character #{character_id}, creating...")
        create_quest_record(character_id, session_quest)

      db_quest ->
        # Update existing quest
        update_quest_record(db_quest, session_quest)
    end
  end

  @doc """
  Persist all quests on logout/disconnect.

  This is a synchronous operation that ensures all quest state is saved
  before the connection terminates.

  ## Parameters

  - `character_id` - The character logging out
  - `session_data` - The final session data

  ## Returns

  `:ok` always (logs errors but doesn't fail logout)
  """
  @spec persist_on_logout(non_neg_integer(), map()) :: :ok
  def persist_on_logout(character_id, session_data) do
    case persist_dirty_quests(character_id, session_data) do
      {:ok, count, _} when count > 0 ->
        Logger.info("Persisted #{count} quests on logout for character #{character_id}")
        :ok

      {:ok, 0, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to persist quests on logout for character #{character_id}: #{inspect(reason)}")
        :ok
    end
  end

  # Private functions

  defp create_quest_record(character_id, session_quest) do
    progress = build_progress_map(session_quest)

    case Quests.accept_quest(character_id, session_quest.quest_id, progress: progress) do
      {:ok, _quest} ->
        Logger.debug("Created quest record #{session_quest.quest_id} for character #{character_id}")
        :ok

      {:error, :already_have_quest} ->
        # Race condition - quest was created elsewhere, try update instead
        case Quests.get_quest(character_id, session_quest.quest_id) do
          nil ->
            {:error, :create_failed}

          db_quest ->
            update_quest_record(db_quest, session_quest)
        end

      {:error, reason} ->
        Logger.error("Failed to create quest #{session_quest.quest_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_quest_record(db_quest, session_quest) do
    progress = build_progress_map(session_quest)

    case Quests.update_progress(db_quest, progress) do
      {:ok, updated_quest} ->
        # Also update state if needed
        maybe_update_state(updated_quest, session_quest.state)

      {:error, reason} ->
        Logger.error("Failed to update quest #{session_quest.quest_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_update_state(db_quest, :complete) when db_quest.state != :complete do
    case Quests.mark_complete(db_quest) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_update_state(_db_quest, _state), do: :ok

  defp build_progress_map(session_quest) do
    objectives =
      Enum.map(session_quest.objectives, fn obj ->
        %{
          "index" => obj.index,
          "current" => obj.current,
          "target" => obj.target,
          "type" => to_string(obj.type)
        }
      end)

    %{"objectives" => objectives, "flags" => %{}}
  end
end
