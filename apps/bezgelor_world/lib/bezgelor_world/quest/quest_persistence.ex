defmodule BezgelorWorld.Quest.QuestPersistence do
  @dialyzer :no_match

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
      {:ok, success, failures, updated_session} = QuestPersistence.persist_dirty_quests(character_id, session_data)

      # Persist a single quest
      :ok = QuestPersistence.persist_quest(character_id, session_quest)
  """

  alias BezgelorDb.Quests
  alias BezgelorWorld.Quest.QuestCache

  require Logger

  @doc """
  Persist all dirty quests from session data to the database.

  Returns the number of quests persisted and updated session_data with
  dirty flags cleared only for successfully persisted quests.

  ## Parameters

  - `character_id` - The character whose quests to persist
  - `session_data` - The session data containing active_quests

  ## Returns

  `{:ok, success_count, failure_count, updated_session_data}`
  """
  @spec persist_dirty_quests(non_neg_integer(), map()) ::
          {:ok, non_neg_integer(), non_neg_integer(), map()}
  def persist_dirty_quests(character_id, session_data) do
    active_quests = session_data[:active_quests] || %{}
    dirty_quests = QuestCache.get_dirty_quests(active_quests)

    if dirty_quests == [] do
      {:ok, 0, 0, session_data}
    else
      Logger.debug("Persisting #{length(dirty_quests)} dirty quests for character #{character_id}")

      # Persist each dirty quest and track results
      results =
        Enum.map(dirty_quests, fn quest ->
          {quest.quest_id, persist_quest(character_id, quest)}
        end)

      # Separate successes from failures
      {successes, failures} = Enum.split_with(results, fn {_id, result} -> result == :ok end)

      success_count = length(successes)
      failure_count = length(failures)

      if failure_count > 0 do
        failed_ids = Enum.map(failures, fn {id, _} -> id end)
        Logger.warning("Failed to persist #{failure_count} quests for character #{character_id}: #{inspect(failed_ids)}")
      end

      # Only clear dirty flags for quests that succeeded
      succeeded_quest_ids = Enum.map(successes, fn {id, _} -> id end)
      updated_active_quests = QuestCache.clear_dirty_flags(active_quests, succeeded_quest_ids)
      updated_session_data = Map.put(session_data, :active_quests, updated_active_quests)

      {:ok, success_count, failure_count, updated_session_data}
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

  # Maximum retry attempts for logout persistence
  @logout_max_retries 3
  # Delay between retries in milliseconds
  @logout_retry_delay_ms 100

  @doc """
  Persist all quests on logout/disconnect.

  This is a synchronous operation that ensures all quest state is saved
  before the connection terminates. Will retry failed quests up to
  #{@logout_max_retries} times with exponential backoff.

  ## Parameters

  - `character_id` - The character logging out
  - `session_data` - The final session data

  ## Returns

  `:ok` always (logs errors but doesn't fail logout)
  """
  @spec persist_on_logout(non_neg_integer(), map()) :: :ok
  def persist_on_logout(character_id, session_data) do
    persist_with_retry(character_id, session_data, @logout_max_retries)
  end

  defp persist_with_retry(character_id, session_data, attempts_remaining) do
    case persist_dirty_quests(character_id, session_data) do
      {:ok, success_count, 0, _updated_session_data} ->
        # All quests persisted successfully
        if success_count > 0 do
          Logger.info("Persisted #{success_count} quests on logout for character #{character_id}")
        end
        :ok

      {:ok, success_count, failure_count, updated_session_data} when attempts_remaining > 1 ->
        # Some quests failed, retry with remaining dirty quests
        Logger.warning(
          "Quest persistence: #{success_count} succeeded, #{failure_count} failed for character #{character_id}. " <>
          "Retrying (#{attempts_remaining - 1} attempts remaining)..."
        )
        Process.sleep(@logout_retry_delay_ms * (@logout_max_retries - attempts_remaining + 1))
        persist_with_retry(character_id, updated_session_data, attempts_remaining - 1)

      {:ok, success_count, failure_count, _updated_session_data} ->
        # Final attempt failed
        Logger.error(
          "Quest persistence FAILED after #{@logout_max_retries} attempts for character #{character_id}: " <>
          "#{success_count} succeeded, #{failure_count} lost"
        )
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
