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
  @compile {:no_warn_undefined, [BezgelorWorld.Quest.QuestCache, BezgelorWorld.Handler.AchievementHandler, BezgelorWorld.Cinematic.CinematicManager, BezgelorWorld.TriggerManager, BezgelorWorld.Creature.ZoneManager, BezgelorWorld.CreatureManager]}

  alias BezgelorProtocol.Packets.World.{ServerEntityCreate, ServerQuestList, ServerPlayerEnteredWorld}
  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.Entity
  alias BezgelorWorld.Handler.AchievementHandler
  alias BezgelorWorld.Quest.QuestCache
  alias BezgelorWorld.TriggerManager
  alias BezgelorWorld.Cinematic.CinematicManager
  alias BezgelorWorld.CreatureManager

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
    # Get spawn location from session or use character's last location
    # spawn_location comes from Zone.spawn_location/1 which returns:
    # %{world_id, zone_id, position: {x, y, z}, rotation: {rx, ry, rz}}
    spawn_location = state.session_data[:spawn_location]

    spawn =
      if spawn_location do
        %{
          position: spawn_location.position,
          rotation: spawn_location.rotation
        }
      else
        %{
          position: {character.location_x || 0.0, character.location_y || 0.0, character.location_z || 0.0},
          rotation: {character.rotation_x || 0.0, character.rotation_y || 0.0, character.rotation_z || 0.0}
        }
      end

    # Build entity spawn packet directly from character (preserves appearance data)
    entity_packet = ServerEntityCreate.from_character(character, spawn)

    # The GUID from from_character is character.id + 0x2000_0000
    guid = entity_packet.guid

    # Create entity for internal state tracking
    entity = Entity.from_character(character, guid)
    entity = %{entity | position: spawn.position, rotation: spawn.rotation}

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

    # Connection PID is self() since handlers run in the Connection GenServer
    connection_pid = self()

    {:ok, achievement_handler} =
      AchievementHandler.start_link(
        connection_pid,
        character.id,
        account_id: account_id
      )

    # Send achievement list to client
    AchievementHandler.send_achievement_list(connection_pid, character.id)

    # Update session state
    state = put_in(state.session_data[:entity_guid], guid)
    state = put_in(state.session_data[:entity], entity)
    state = put_in(state.session_data[:in_world], true)
    state = put_in(state.session_data[:active_quests], active_quests)
    state = put_in(state.session_data[:completed_quest_ids], completed_quest_ids)
    state = put_in(state.session_data[:achievement_handler], achievement_handler)

    # Load trigger volumes for the zone
    spawn_location = state.session_data[:spawn_location]
    zone_id = if spawn_location, do: spawn_location.zone_id, else: character.world_zone_id
    world_id = if spawn_location, do: spawn_location.world_id, else: character.world_id

    triggers = TriggerManager.load_zone_triggers(zone_id)
    state = put_in(state.session_data[:zone_triggers], triggers)
    state = put_in(state.session_data[:active_triggers], MapSet.new())
    state = put_in(state.session_data[:zone_id], zone_id)
    state = put_in(state.session_data[:world_id], world_id)

    Logger.debug("Loaded #{length(triggers)} trigger volumes for zone #{zone_id}")

    Logger.info(
      "Player '#{character.name}' (GUID: #{guid}, Level: #{character.level}) entered world " <>
        "zone_id=#{zone_id} world_id=#{world_id} at #{inspect(entity.position)} with #{map_size(active_quests)} quests"
    )

    # Schedule periodic quest persistence timer
    send(self(), :schedule_quest_persistence)

    # Build ServerPlayerEnteredWorld packet - this dismisses the loading screen
    entered_world_writer = PacketWriter.new()
    {:ok, entered_world_writer} = ServerPlayerEnteredWorld.write(%ServerPlayerEnteredWorld{}, entered_world_writer)
    entered_world_data = PacketWriter.to_binary(entered_world_writer)

    # Check for zone entry cinematics (e.g., tutorial intro)
    cinematic_packets = build_cinematic_packets(state.session_data, zone_id)

    # Build creature spawn packets for creatures near the player
    creature_packets = build_creature_packets(spawn.position)

    Logger.debug("Sending #{length(creature_packets)} creature entity packets to player at #{inspect(spawn.position)}")

    # Base packets always sent
    base_packets = [
      {:server_entity_create, entity_packet_data},
      {:server_quest_list, quest_packet_data}
    ]

    # Order: player entity, creatures, quest list, cinematics, entered_world (dismisses loading)
    final_packets =
      base_packets ++
      creature_packets ++
      cinematic_packets ++
      [{:server_player_entered_world, entered_world_data}]

    {:reply_multi_world_encrypted, final_packets, state}
  end

  # Build creature entity packets for creatures near the player
  # Uses range filtering to avoid overwhelming the client with too many entities
  @creature_view_range 200.0

  defp build_creature_packets(position) do
    # Get creatures within view range of the player's position
    creatures = CreatureManager.get_creatures_in_range(position, @creature_view_range)

    Enum.map(creatures, fn creature_state ->
      # Skip dead creatures
      if creature_state.ai.state == :dead do
        nil
      else
        packet = ServerEntityCreate.from_creature(creature_state)
        writer = PacketWriter.new()
        {:ok, writer} = ServerEntityCreate.write(packet, writer)
        data = PacketWriter.to_binary(writer)
        {:server_entity_create, data}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Build cinematic packets if a cinematic should play on zone entry
  defp build_cinematic_packets(session_data, zone_id) do
    case CinematicManager.on_zone_enter(session_data, zone_id) do
      {:play, packets} ->
        Logger.info("Playing zone entry cinematic with #{length(packets)} packets")
        encode_cinematic_packets(packets)

      :none ->
        []
    end
  end

  # Encode a list of cinematic packet structs to binary format
  defp encode_cinematic_packets(packets) do
    Enum.map(packets, fn packet ->
      opcode = packet.__struct__.opcode()
      writer = PacketWriter.new()
      {:ok, writer} = packet.__struct__.write(packet, writer)
      data = PacketWriter.to_binary(writer)
      {opcode, data}
    end)
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
end
