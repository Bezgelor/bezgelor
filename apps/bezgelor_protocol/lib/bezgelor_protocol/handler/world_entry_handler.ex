defmodule BezgelorProtocol.Handler.WorldEntryHandler do
  @moduledoc """
  Handler for ClientEnteredWorld packets.

  Called when the client finishes loading the world after receiving
  ServerWorldEnter. Spawns the player entity and sends initial game state.

  ## Flow

  1. Verify character is selected
  2. Generate unique entity GUID
  3. Create player entity
  4. Send ServerEntityCreate to spawn the player
  5. Load quests and send ServerQuestList
  6. Mark session as in-world
  """

  @behaviour BezgelorProtocol.Handler
  @compile {:no_warn_undefined, [BezgelorWorld.Quest.QuestCache, BezgelorWorld.Handler.AchievementHandler]}

  import Bitwise

  alias BezgelorProtocol.Packets.World.{ServerEntityCreate, ServerQuestList}
  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.Entity
  alias BezgelorWorld.Handler.AchievementHandler
  alias BezgelorWorld.Quest.QuestCache

  require Logger

  @impl true
  def handle(_payload, state) do
    character = state.session_data[:character]

    if is_nil(character) do
      Logger.warning("ClientEnteredWorld received without character selected")
      {:error, :no_character_selected}
    else
      spawn_player(character, state)
    end
  end

  defp spawn_player(character, state) do
    # Generate unique entity GUID
    guid = generate_guid(character)

    # Create entity from character data
    entity = Entity.from_character(character, guid)

    # Build entity spawn packet
    entity_packet = ServerEntityCreate.from_entity(entity)

    # Encode entity packet
    writer = PacketWriter.new()
    {:ok, writer} = ServerEntityCreate.write(entity_packet, writer)
    entity_packet_data = PacketWriter.to_binary(writer)

    # Load quests for character
    {:ok, active_quests, completed_quest_ids} = QuestCache.load_quests_for_character(character.id)

    # Build quest list packet
    quest_list_packet = build_quest_list_packet(active_quests)
    quest_writer = PacketWriter.new()
    {:ok, quest_writer} = ServerQuestList.write(quest_list_packet, quest_writer)
    quest_packet_data = PacketWriter.to_binary(quest_writer)

    # Start achievement handler for this character
    account_id = state.session_data[:account_id]

    {:ok, achievement_handler} =
      AchievementHandler.start_link(
        state.connection_pid,
        character.id,
        account_id: account_id
      )

    # Send achievement list to client
    AchievementHandler.send_achievement_list(state.connection_pid, character.id)

    # Update session state
    state = put_in(state.session_data[:entity_guid], guid)
    state = put_in(state.session_data[:entity], entity)
    state = put_in(state.session_data[:in_world], true)
    state = put_in(state.session_data[:active_quests], active_quests)
    state = put_in(state.session_data[:completed_quest_ids], completed_quest_ids)
    state = put_in(state.session_data[:achievement_handler], achievement_handler)

    Logger.info(
      "Player '#{character.name}' (GUID: #{guid}) entered world at " <>
        "#{inspect(entity.position)} with #{map_size(active_quests)} quests"
    )

    # Schedule periodic quest persistence timer
    send(self(), :schedule_quest_persistence)

    {:reply_multi, [
      {:server_entity_create, entity_packet_data},
      {:server_quest_list, quest_packet_data}
    ], state}
  end

  # Convert session quests to format expected by ServerQuestList packet
  defp build_quest_list_packet(active_quests) do
    quests =
      active_quests
      |> Map.values()
      |> Enum.map(fn quest ->
        # Convert session objectives to packet format
        objectives =
          Enum.map(quest.objectives, fn obj ->
            %{"current" => obj.current, "target" => obj.target}
          end)

        %{
          quest_id: quest.quest_id,
          state: quest.state,
          progress: %{"objectives" => objectives}
        }
      end)

    %ServerQuestList{quests: quests}
  end

  # Generate a unique GUID for the entity
  # In a production system, this would be managed by WorldManager
  defp generate_guid(character) do
    # Simple GUID: combine character ID with timestamp for uniqueness
    # High bits: entity type (1 = player)
    # Low bits: character_id + monotonic counter
    entity_type = 1
    counter = :erlang.unique_integer([:positive, :monotonic])

    # Format: [type:4][reserved:12][character_id:24][counter:24]
    bsl(entity_type, 60) ||| bsl(character.id &&& 0xFFFFFF, 24) ||| (counter &&& 0xFFFFFF)
  end
end
