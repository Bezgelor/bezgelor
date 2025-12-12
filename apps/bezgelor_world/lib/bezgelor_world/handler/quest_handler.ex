defmodule BezgelorWorld.Handler.QuestHandler do
  @moduledoc """
  Handles quest-related packets and events.

  Processes quest acceptance, abandonment, turn-in, and progress updates.
  """

  alias BezgelorDb.{Characters, Quests}
  alias BezgelorProtocol.Packets.World.{
    ClientAcceptQuest,
    ClientAbandonQuest,
    ClientTurnInQuest,
    ServerQuestList,
    ServerQuestAdd,
    ServerQuestUpdate,
    ServerQuestRemove
  }

  alias BezgelorWorld.Quest.{PrerequisiteChecker, RewardHandler}

  require Logger

  @doc """
  Send full quest log to client (called on login).
  """
  @spec send_quest_log(pid(), integer()) :: :ok
  def send_quest_log(connection_pid, character_id) do
    quests = Quests.get_active_quests(character_id)

    packet = %ServerQuestList{quests: quests}
    send(connection_pid, {:send_packet, packet})

    :ok
  end

  @doc """
  Handle quest accept request.
  """
  @spec handle_accept_quest(pid(), integer(), ClientAcceptQuest.t(), map()) :: :ok
  def handle_accept_quest(connection_pid, character_id, %ClientAcceptQuest{} = packet, quest_data) do
    # quest_data should contain objectives from BezgelorData lookup
    objectives = Map.get(quest_data, :objectives, [])
    progress = Quests.init_progress(objectives)

    case Quests.accept_quest(character_id, packet.quest_id, progress: progress) do
      {:ok, quest} ->
        objectives_data = get_in(quest.progress, ["objectives"]) || []

        add_packet = %ServerQuestAdd{
          quest_id: packet.quest_id,
          objectives: objectives_data
        }

        send(connection_pid, {:send_packet, add_packet})
        Logger.debug("Character #{character_id} accepted quest #{packet.quest_id}")

      {:error, :quest_log_full} ->
        Logger.warning("Quest log full for character #{character_id}")
        # TODO: Send error packet

      {:error, :already_have_quest} ->
        Logger.warning("Character #{character_id} already has quest #{packet.quest_id}")

      {:error, reason} ->
        Logger.error("Failed to accept quest: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Handle quest abandon request.
  """
  @spec handle_abandon_quest(pid(), integer(), ClientAbandonQuest.t()) :: :ok
  def handle_abandon_quest(connection_pid, character_id, %ClientAbandonQuest{} = packet) do
    case Quests.abandon_quest(character_id, packet.quest_id) do
      {:ok, _} ->
        remove_packet = %ServerQuestRemove{
          quest_id: packet.quest_id,
          reason: :abandoned
        }

        send(connection_pid, {:send_packet, remove_packet})
        Logger.debug("Character #{character_id} abandoned quest #{packet.quest_id}")

      {:error, :not_found} ->
        Logger.warning("Character #{character_id} tried to abandon unknown quest #{packet.quest_id}")
    end

    :ok
  end

  @doc """
  Handle quest turn-in request.

  The quest_data map should include:
  - :reputation_rewards - list of {faction_id, amount} tuples
  - :xp_reward - XP to grant
  - :gold_reward - gold to grant
  """
  @spec handle_turn_in_quest(pid(), integer(), ClientTurnInQuest.t(), map()) :: :ok
  def handle_turn_in_quest(connection_pid, character_id, %ClientTurnInQuest{} = packet, _quest_data \\ %{}) do
    case Quests.turn_in_quest(character_id, packet.quest_id) do
      {:ok, _history} ->
        remove_packet = %ServerQuestRemove{
          quest_id: packet.quest_id,
          reason: :completed
        }

        send(connection_pid, {:send_packet, remove_packet})
        Logger.debug("Character #{character_id} turned in quest #{packet.quest_id}")

        # Grant rewards using the RewardHandler
        case RewardHandler.grant_quest_rewards(connection_pid, character_id, packet.quest_id) do
          {:ok, summary} ->
            Logger.debug("Quest rewards granted: #{inspect(summary)}")

          {:error, reason} ->
            Logger.warning("Failed to grant quest rewards: #{inspect(reason)}")
        end

        :ok

      {:error, :not_found} ->
        Logger.warning("Character #{character_id} tried to turn in unknown quest #{packet.quest_id}")

      {:error, :not_complete} ->
        Logger.warning("Character #{character_id} tried to turn in incomplete quest #{packet.quest_id}")

      {:error, reason} ->
        Logger.error("Failed to turn in quest: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Update quest objective progress and notify client.

  Called when game events occur (kill mob, collect item, etc.).
  """
  @spec update_objective(pid(), integer(), integer(), integer(), integer()) :: :ok
  def update_objective(connection_pid, character_id, quest_id, objective_index, new_value) do
    case Quests.get_quest(character_id, quest_id) do
      nil ->
        :ok

      quest ->
        case Quests.update_objective(quest, objective_index, new_value) do
          {:ok, updated_quest} ->
            # Check if quest is now complete
            state =
              if Quests.all_objectives_complete?(updated_quest) do
                {:ok, _} = Quests.mark_complete(updated_quest)
                :complete
              else
                :accepted
              end

            update_packet = %ServerQuestUpdate{
              quest_id: quest_id,
              state: state,
              objective_index: objective_index,
              current: new_value
            }

            send(connection_pid, {:send_packet, update_packet})

          {:error, _} ->
            :ok
        end
    end

    :ok
  end

  @doc """
  Increment quest objective and notify client.

  Convenience wrapper for update_objective when incrementing by 1.
  """
  @spec increment_objective(pid(), integer(), integer(), integer()) :: :ok
  def increment_objective(connection_pid, character_id, quest_id, objective_index) do
    case Quests.get_quest(character_id, quest_id) do
      nil ->
        :ok

      quest ->
        case Quests.get_objective_progress(quest, objective_index) do
          nil ->
            :ok

          {current, target} ->
            new_value = min(current + 1, target)
            update_objective(connection_pid, character_id, quest_id, objective_index, new_value)
        end
    end
  end

  @doc """
  Process a kill event for quest objectives.

  Checks all active quests for kill objectives matching the creature.
  """
  @spec process_kill(pid(), integer(), integer()) :: :ok
  def process_kill(connection_pid, character_id, creature_id) do
    quests = Quests.get_active_quests(character_id)

    Enum.each(quests, fn quest ->
      objectives = get_in(quest.progress, ["objectives"]) || []

      Enum.each(objectives, fn obj ->
        if obj["type"] == "kill" and obj["creature_id"] == creature_id do
          current = obj["current"] || 0
          target = obj["target"] || 1

          if current < target do
            increment_objective(connection_pid, character_id, quest.quest_id, obj["index"])
          end
        end
      end)
    end)

    :ok
  end

  @doc """
  Process an item collection event for quest objectives.
  """
  @spec process_item_collect(pid(), integer(), integer(), integer()) :: :ok
  def process_item_collect(connection_pid, character_id, item_id, count) do
    quests = Quests.get_active_quests(character_id)

    Enum.each(quests, fn quest ->
      objectives = get_in(quest.progress, ["objectives"]) || []

      Enum.each(objectives, fn obj ->
        if obj["type"] == "item" and obj["item_id"] == item_id do
          current = obj["current"] || 0
          target = obj["target"] || 1
          new_value = min(current + count, target)

          if new_value > current do
            update_objective(connection_pid, character_id, quest.quest_id, obj["index"], new_value)
          end
        end
      end)
    end)

    :ok
  end

  @doc """
  Check if character has completed a quest (for prerequisites).
  """
  @spec has_completed_quest?(integer(), integer()) :: boolean()
  def has_completed_quest?(character_id, quest_id) do
    Quests.has_completed?(character_id, quest_id)
  end

  @doc """
  Check if character can accept a quest.

  Validates prerequisites, level requirements, etc.
  """
  @spec can_accept_quest?(integer(), map()) :: boolean()
  def can_accept_quest?(character_id, quest_data) do
    character = get_character_data(character_id)

    if character do
      case PrerequisiteChecker.can_accept_quest?(character, quest_data) do
        {:ok, true} -> true
        {:error, _reason} -> false
      end
    else
      false
    end
  end

  # Get character data for prerequisite checks
  defp get_character_data(character_id) do
    case Characters.get_character(character_id) do
      nil ->
        nil

      character ->
        %{
          id: character.id,
          level: character.level,
          race_id: character.race_id,
          class_id: character.class_id,
          faction_id: character.faction_id
        }
    end
  end
end
