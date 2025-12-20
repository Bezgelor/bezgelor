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
  @compile {:no_warn_undefined,
            [
              BezgelorWorld.Abilities,
              BezgelorWorld.Quest.QuestCache,
              BezgelorWorld.Handler.AchievementHandler,
              BezgelorWorld.Cinematic.CinematicManager,
              BezgelorWorld.TriggerManager,
              BezgelorWorld.Creature.ZoneManager,
              BezgelorWorld.CreatureManager,
              BezgelorWorld.WorldManager,
              BezgelorWorld.VisibilityBroadcaster
            ]}
  # Suppress warning for {:play, packets} clause - cinematics are intentionally disabled
  # but this code is correct for when they're re-enabled
  @dialyzer {:nowarn_function, build_cinematic_packets: 2}

  alias BezgelorProtocol.Packets.World.{
    ServerEntityCreate,
    ServerPlayerEnteredWorld,
    ServerQuestList
  }

  alias BezgelorProtocol.PacketWriter
  alias BezgelorCore.Entity
  alias BezgelorWorld.Handler.AchievementHandler
  alias BezgelorWorld.Quest.QuestCache
  alias BezgelorWorld.TriggerManager
  alias BezgelorWorld.Cinematic.CinematicManager
  alias BezgelorWorld.CreatureManager
  alias BezgelorWorld.WorldManager
  alias BezgelorWorld.VisibilityBroadcaster

  require Logger
  import Bitwise

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
          position:
            {character.location_x || 0.0, character.location_y || 0.0,
             character.location_z || 0.0},
          rotation:
            {character.rotation_x || 0.0, character.rotation_y || 0.0,
             character.rotation_z || 0.0}
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

    # Note: Inventory is sent via ServerPlayerCreate in CharacterSelectHandler during loading.
    # ServerItemAdd packets are only for runtime item additions, not initial load.

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
    # Single instance per zone for now
    state = put_in(state.session_data[:instance_id], 1)
    state = put_in(state.session_data[:world_id], world_id)

    Logger.debug("Loaded #{length(triggers)} trigger volumes for zone #{zone_id}")

    Logger.info(
      "Player '#{character.name}' (GUID: #{guid}, Level: #{character.level}) entered world " <>
        "zone_id=#{zone_id} world_id=#{world_id} at #{inspect(entity.position)} with #{map_size(active_quests)} quests"
    )

    # Register session with WorldManager for multiplayer visibility
    # instance_id = 1 for now (single instance per zone)
    instance_id = 1
    WorldManager.register_session(account_id, character.id, character.name, self())
    WorldManager.set_entity_guid(account_id, guid)
    # Use world_id (not zone_id) since Zone.Instance is keyed by world_id
    WorldManager.update_session_zone(account_id, world_id, instance_id)

    # Broadcast player spawn to other players in the zone (use world_id to match Zone.Instance)
    VisibilityBroadcaster.broadcast_player_spawn(character, world_id, instance_id, guid)

    # Schedule periodic quest persistence timer
    send(self(), :schedule_quest_persistence)

    # Build ServerPlayerEnteredWorld packet - this dismisses the loading screen
    entered_world_writer = PacketWriter.new()

    {:ok, entered_world_writer} =
      ServerPlayerEnteredWorld.write(%ServerPlayerEnteredWorld{}, entered_world_writer)

    entered_world_data = PacketWriter.to_binary(entered_world_writer)

    # Check for zone entry cinematics (e.g., tutorial intro)
    cinematic_packets = build_cinematic_packets(state.session_data, zone_id)

    # Build creature spawn packets for creatures near the player
    creature_packets = build_creature_packets(spawn.position)

    Logger.debug(
      "Sending #{length(creature_packets)} creature entity packets to player at #{inspect(spawn.position)}"
    )

    ability_packets = BezgelorProtocol.AbilityPackets.build(character)

    # Base packets always sent
    base_packets = [
      {:server_entity_create, entity_packet_data},
      {:server_quest_list, quest_packet_data}
    ]

    # Order: player entity, creatures, quest list, cinematics, entered_world (dismisses loading)
    # Note: Inventory already sent via ServerPlayerCreate in CharacterSelectHandler
    final_packets =
      base_packets ++
        creature_packets ++
        cinematic_packets ++
        [{:server_player_entered_world, entered_world_data}] ++
        ability_packets

    {:reply_multi_world_encrypted, final_packets, state}
  end

  # Build creature entity packets for creatures near the player
  # Uses range filtering to avoid overwhelming the client with too many entities
  # Also sends movement packets for creatures that are already moving
  @creature_view_range 200.0

  defp build_creature_packets(position) do
    alias BezgelorProtocol.Packets.World.ServerEntityCommand

    # Get creatures within view range of the player's position
    # Use a short timeout to avoid blocking login if spawn loading is in progress
    creatures =
      try do
        CreatureManager.get_creatures_in_range(position, @creature_view_range)
      catch
        :exit, {:timeout, _} ->
          Logger.warning("CreatureManager timeout - spawn loading may still be in progress")
          []

        :exit, _ ->
          []
      end

    # Build packets and count what we're sending
    {packets, stats} =
      Enum.reduce(
        creatures,
        {[], %{entities: 0, movements: 0, skipped_stale: 0, initial_patrol: 0}},
        fn creature_state, {acc_packets, acc_stats} ->
          # Skip dead creatures
          if creature_state.ai.state == :dead do
            {acc_packets, acc_stats}
          else
            # Build entity create packet
            create_packet = ServerEntityCreate.from_creature(creature_state)
            writer = PacketWriter.new()
            {:ok, writer} = ServerEntityCreate.write(create_packet, writer)
            create_data = PacketWriter.to_binary(writer)

            # Build movement packets based on creature state
            ai = creature_state.ai

            {movement_packets, updated_stats} =
              cond do
                # Already moving - send current movement
                ai.state in [:patrol, :wandering] and length(ai.movement_path) > 1 ->
                  packets = build_movement_packet(creature_state)

                  if packets == [] do
                    {[], Map.update(acc_stats, :skipped_stale, 1, &(&1 + 1))}
                  else
                    {packets, Map.update(acc_stats, :movements, 1, &(&1 + 1))}
                  end

                # Idle but should be patrolling - start patrol now!
                ai.state == :idle and ai.patrol_enabled and length(ai.patrol_waypoints) > 0 ->
                  packets = build_initial_patrol_packet(creature_state)

                  if packets == [] do
                    Logger.warning(
                      "build_initial_patrol_packet returned empty for creature with #{length(ai.patrol_waypoints)} waypoints"
                    )

                    {[], acc_stats}
                  else
                    {packets, Map.update(acc_stats, :initial_patrol, 1, &(&1 + 1))}
                  end

                # Idle with patrol_enabled but no waypoints - log for debug
                ai.state == :idle and ai.patrol_enabled ->
                  Logger.warning(
                    "Creature has patrol_enabled but #{length(ai.patrol_waypoints)} waypoints"
                  )

                  {[], acc_stats}

                # Nothing to do
                true ->
                  {[], acc_stats}
              end

            new_stats = Map.update(updated_stats, :entities, 1, &(&1 + 1))
            {acc_packets ++ [{:server_entity_create, create_data}] ++ movement_packets, new_stats}
          end
        end
      )

    Logger.info("Zone entry packets: #{inspect(stats)}")
    packets
  end

  # Build patrol movement packet for a creature that should start patrolling
  defp build_initial_patrol_packet(creature_state) do
    alias BezgelorProtocol.Packets.World.ServerEntityCommand
    alias BezgelorCore.Movement

    ai = creature_state.ai
    guid = creature_state.entity.guid
    position = creature_state.entity.position

    # Get first waypoint as target
    first_waypoint = Enum.at(ai.patrol_waypoints, 0)

    if first_waypoint do
      target_pos =
        case first_waypoint do
          %{position: {x, y, z}} -> {x, y, z}
          %{position: [x, y, z]} -> {x, y, z}
          {x, y, z} -> {x, y, z}
          [x, y, z] -> {x, y, z}
          _ -> nil
        end

      if target_pos do
        # Generate path from current position to first waypoint
        path = Movement.direct_path(position, target_pos)

        if length(path) > 1 do
          speed = ai.patrol_speed || 3.0

          state_command = %{type: :set_state, state: 0x02}
          move_defaults = %{type: :set_move_defaults, blend: false}
          rotation_defaults = %{type: :set_rotation_defaults, blend: false}

          path_command = %{
            type: :set_position_path,
            positions: path,
            speed: speed,
            spline_type: :linear,
            spline_mode: :one_shot,
            offset: 0,
            blend: true
          }

          packet = %ServerEntityCommand{
            guid: guid,
            time: System.system_time(:millisecond) |> band(0xFFFFFFFF),
            time_reset: false,
            server_controlled: true,
            commands: [state_command, move_defaults, rotation_defaults, path_command]
          }

          writer = PacketWriter.new()
          {:ok, writer} = ServerEntityCommand.write(packet, writer)
          data = PacketWriter.to_binary(writer)

          Logger.debug("Starting initial patrol for creature #{guid} to #{inspect(target_pos)}")
          [{:server_entity_command, data}]
        else
          []
        end
      else
        []
      end
    else
      []
    end
  end

  # Build a movement packet for a creature that's already moving
  # Calculates remaining path based on elapsed time to avoid sending stale movement
  defp build_movement_packet(creature_state) do
    alias BezgelorProtocol.Packets.World.ServerEntityCommand
    alias BezgelorCore.Movement

    ai = creature_state.ai
    guid = creature_state.entity.guid
    path = ai.movement_path
    speed = if ai.state == :patrol, do: ai.patrol_speed, else: ai.wander_speed

    # Calculate how much time has elapsed since movement started
    now = System.monotonic_time(:millisecond)
    elapsed = if ai.movement_start_time, do: now - ai.movement_start_time, else: 0
    duration = ai.movement_duration || 0

    # If more than 80% of movement time has elapsed, the AI tick will soon
    # determine movement is complete and start a new segment. Don't send stale movement.
    # Instead, let the creature appear at its last path point (destination).
    if duration > 0 and elapsed >= duration * 0.8 do
      []
    else
      # Calculate remaining path from estimated current position
      {adjusted_path, _remaining_duration} =
        if elapsed > 0 and duration > 0 and length(path) >= 2 do
          # Estimate current position along the path
          progress = min(1.0, elapsed / duration)
          current_pos = Movement.interpolate_path(path, progress)

          # Build remaining path from current position to destination
          destination = List.last(path)
          remaining_path = Movement.direct_path(current_pos, destination)
          # At least 100ms
          remaining_duration = max(100, duration - elapsed)

          {remaining_path, remaining_duration}
        else
          {path, duration}
        end

      # Only send if we have a valid path
      if length(adjusted_path) >= 2 do
        # Build movement commands (same as CreatureManager.broadcast_creature_movement)
        state_command = %{type: :set_state, state: 0x02}
        move_defaults = %{type: :set_move_defaults, blend: false}
        rotation_defaults = %{type: :set_rotation_defaults, blend: false}

        path_command = %{
          type: :set_position_path,
          positions: adjusted_path,
          speed: speed,
          spline_type: :linear,
          spline_mode: :one_shot,
          offset: 0,
          blend: true
        }

        packet = %ServerEntityCommand{
          guid: guid,
          time: System.system_time(:millisecond) |> band(0xFFFFFFFF),
          time_reset: false,
          server_controlled: true,
          commands: [state_command, move_defaults, rotation_defaults, path_command]
        }

        writer = PacketWriter.new()
        {:ok, writer} = ServerEntityCommand.write(packet, writer)
        data = PacketWriter.to_binary(writer)

        [{:server_entity_command, data}]
      else
        []
      end
    end
  end

  # Build cinematic packets if a cinematic should play on zone entry
  # NOTE: Cinematics are currently disabled in CinematicManager (see its moduledoc).
  # When re-enabled, restore the {:play, packets} handling here.
  defp build_cinematic_packets(session_data, zone_id) do
    # Returns :none while cinematics are disabled
    _ = CinematicManager.on_zone_enter(session_data, zone_id)
    []
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
