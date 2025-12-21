defmodule BezgelorWorld.Handler.QuestHandler do
  @moduledoc """
  Handles quest-related packets and events.

  Processes quest acceptance, abandonment, turn-in, and progress updates.
  Uses SessionQuestManager for session-based quest tracking.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorDb.{Characters, Quests}
  alias BezgelorProtocol.PacketReader

  alias BezgelorProtocol.Packets.World.{
    ClientAcceptQuest,
    ClientAbandonQuest,
    ClientTurnInQuest
  }

  alias BezgelorWorld.Quest.{PrerequisiteChecker, RewardHandler, SessionQuestManager}

  require Logger

  @telemetry_events [
    %{
      event: [:bezgelor, :quest, :accepted],
      measurements: [:count],
      tags: [:character_id, :quest_id],
      description: "Quest accepted by player",
      domain: :quest
    },
    %{
      event: [:bezgelor, :quest, :completed],
      measurements: [:count],
      tags: [:character_id, :quest_id],
      description: "Quest completed by player",
      domain: :quest
    },
    %{
      event: [:bezgelor, :quest, :abandoned],
      measurements: [:count],
      tags: [:character_id, :quest_id],
      description: "Quest abandoned by player",
      domain: :quest
    }
  ]

  def telemetry_events, do: @telemetry_events

  defp emit_quest_telemetry(event_type, character_id, quest_id) do
    :telemetry.execute(
      [:bezgelor, :quest, event_type],
      %{count: 1},
      %{character_id: character_id, quest_id: quest_id}
    )
  end

  # ============================================================================
  # Handler Behaviour
  # ============================================================================

  @impl true
  def handle(payload, state) do
    # Determine which packet type based on opcode in state
    opcode = state[:current_opcode]
    reader = PacketReader.new(payload)

    result =
      case opcode do
        :client_accept_quest ->
          handle_accept_packet(reader, state)

        :client_abandon_quest ->
          handle_abandon_packet(reader, state)

        :client_turn_in_quest ->
          handle_turn_in_packet(reader, state)

        :client_quest_share ->
          # Quest sharing not yet implemented
          Logger.debug("Quest share received but not implemented")
          {:ok, state}

        _ ->
          Logger.warning("Unknown quest opcode: #{inspect(opcode)}")
          {:ok, state}
      end

    result
  end

  defp handle_accept_packet(reader, state) do
    case ClientAcceptQuest.read(reader) do
      {:ok, packet, _reader} ->
        character_id = state.session_data[:character_id]

        case SessionQuestManager.accept_quest(state.session_data, character_id, packet.quest_id) do
          {:ok, updated_session, {opcode, packet_data}} ->
            emit_quest_telemetry(:accepted, character_id, packet.quest_id)
            updated_state = %{state | session_data: updated_session}
            {:reply, opcode, packet_data, updated_state}

          {:error, :quest_log_full} ->
            Logger.warning("Quest log full for character #{character_id}")
            {:ok, state}

          {:error, :already_have_quest} ->
            Logger.warning("Character #{character_id} already has quest #{packet.quest_id}")
            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to accept quest: #{inspect(reason)}")
            {:ok, state}
        end

      {:error, reason} ->
        Logger.warning("Failed to parse ClientAcceptQuest: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_abandon_packet(reader, state) do
    case ClientAbandonQuest.read(reader) do
      {:ok, packet, _reader} ->
        character_id = state.session_data[:character_id]

        case SessionQuestManager.abandon_quest(state.session_data, character_id, packet.quest_id) do
          {:ok, updated_session, {opcode, packet_data}} ->
            emit_quest_telemetry(:abandoned, character_id, packet.quest_id)
            updated_state = %{state | session_data: updated_session}
            {:reply, opcode, packet_data, updated_state}

          {:error, :quest_not_found} ->
            Logger.warning(
              "Character #{character_id} tried to abandon unknown quest #{packet.quest_id}"
            )

            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to abandon quest: #{inspect(reason)}")
            {:ok, state}
        end

      {:error, reason} ->
        Logger.warning("Failed to parse ClientAbandonQuest: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_turn_in_packet(reader, state) do
    case ClientTurnInQuest.read(reader) do
      {:ok, packet, _reader} ->
        character_id = state.session_data[:character_id]
        connection_pid = self()

        case SessionQuestManager.turn_in_quest(state.session_data, character_id, packet.quest_id) do
          {:ok, updated_session, {opcode, packet_data}} ->
            emit_quest_telemetry(:completed, character_id, packet.quest_id)
            updated_state = %{state | session_data: updated_session}

            # Grant rewards using the RewardHandler
            case RewardHandler.grant_quest_rewards(connection_pid, character_id, packet.quest_id) do
              {:ok, summary} ->
                Logger.debug("Quest rewards granted: #{inspect(summary)}")

              {:error, reason} ->
                Logger.warning("Failed to grant quest rewards: #{inspect(reason)}")
            end

            {:reply, opcode, packet_data, updated_state}

          {:error, :quest_not_found} ->
            Logger.warning(
              "Character #{character_id} tried to turn in unknown quest #{packet.quest_id}"
            )

            {:ok, state}

          {:error, :quest_not_complete} ->
            Logger.warning(
              "Character #{character_id} tried to turn in incomplete quest #{packet.quest_id}"
            )

            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to turn in quest: #{inspect(reason)}")
            {:ok, state}
        end

      {:error, reason} ->
        Logger.warning("Failed to parse ClientTurnInQuest: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # Public API - Prerequisite Checking
  # ============================================================================

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
