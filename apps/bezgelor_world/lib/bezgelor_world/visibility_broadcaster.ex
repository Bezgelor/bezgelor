defmodule BezgelorWorld.VisibilityBroadcaster do
  @moduledoc """
  Broadcasts entity visibility events to players in the same zone.

  Handles:
  - Player spawn (ServerEntityCreate to zone)
  - Player despawn (ServerEntityDestroy to zone)
  - Player movement (ServerEntityCommand to zone)

  Uses zone-based visibility: all players in the same zone instance
  can see each other. This matches WildStar's original behavior.
  """

  alias BezgelorWorld.Zone.Instance, as: ZoneInstance
  alias BezgelorProtocol.Packets.World.{ServerEntityCreate, ServerEntityDestroy}
  alias BezgelorProtocol.PacketWriter

  require Logger

  @doc """
  Broadcast a player spawn to all other players in the zone.

  Called when a player enters a zone or becomes visible.
  """
  @spec broadcast_player_spawn(map(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok
  def broadcast_player_spawn(character, zone_id, instance_id, entity_guid) do
    # Build spawn location from character (uses location_x/y/z fields)
    spawn = %{
      position: {
        character.location_x || 0.0,
        character.location_y || 0.0,
        character.location_z || 0.0
      },
      rotation: {0.0, 0.0, character.rotation_z || 0.0}
    }

    # Build entity create packet
    entity_packet = ServerEntityCreate.from_character(character, spawn)

    # Serialize to binary
    case serialize_packet(entity_packet) do
      {:ok, packet_data} ->
        # Broadcast to zone, excluding the spawning player
        ZoneInstance.broadcast(
          {zone_id, instance_id},
          {:server_entity_create, packet_data, entity_guid}
        )

        Logger.debug(
          "[Visibility] Broadcast player spawn: #{character.name} (guid=#{entity_guid}) to zone #{zone_id}"
        )

        :ok

      {:error, reason} ->
        Logger.warning("[Visibility] Failed to serialize player spawn packet: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Broadcast a player despawn to all other players in the zone.

  Called when a player leaves a zone, disconnects, or becomes invisible.
  """
  @spec broadcast_player_despawn(non_neg_integer(), non_neg_integer(), non_neg_integer(), atom()) ::
          :ok
  def broadcast_player_despawn(entity_guid, zone_id, instance_id, reason \\ :out_of_range) do
    # Build entity destroy packet
    destroy_packet = %ServerEntityDestroy{
      guid: entity_guid,
      reason: reason
    }

    # Serialize to binary
    case serialize_packet(destroy_packet) do
      {:ok, packet_data} ->
        # Broadcast to zone, excluding the despawning player
        ZoneInstance.broadcast(
          {zone_id, instance_id},
          {:server_entity_destroy, packet_data, entity_guid}
        )

        Logger.debug(
          "[Visibility] Broadcast player despawn: guid=#{entity_guid} reason=#{reason} to zone #{zone_id}"
        )

        :ok

      {:error, reason} ->
        Logger.warning(
          "[Visibility] Failed to serialize player despawn packet: #{inspect(reason)}"
        )

        :ok
    end
  end

  @doc """
  Broadcast raw client movement to other players in the zone.

  The client sends ClientEntityCommand packets for movement. We relay
  these to other players so they see the movement. The packet is forwarded
  as-is since it contains all the movement commands.
  """
  @spec broadcast_player_movement(
          non_neg_integer(),
          binary(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def broadcast_player_movement(entity_guid, movement_data, zone_id, instance_id) do
    # Forward movement packet to zone, excluding the moving player
    ZoneInstance.broadcast(
      {zone_id, instance_id},
      {:server_entity_command, movement_data, entity_guid}
    )

    :ok
  end

  @doc """
  Build and broadcast a ServerEntityCommand for player position update.

  Used when we need to send a position update synthesized from server state
  rather than relaying client movement.
  """
  @spec broadcast_player_position(
          non_neg_integer(),
          {float(), float(), float()},
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
  def broadcast_player_position(entity_guid, position, zone_id, instance_id) do
    alias BezgelorProtocol.Packets.World.ServerEntityCommand

    # Build position command packet
    command_packet = %ServerEntityCommand{
      guid: entity_guid,
      time: :os.system_time(:millisecond) |> rem(0xFFFFFFFF),
      time_reset: false,
      server_controlled: false,
      commands: [
        %{type: :set_position, position: position, blend: true}
      ]
    }

    case serialize_packet(command_packet) do
      {:ok, packet_data} ->
        ZoneInstance.broadcast(
          {zone_id, instance_id},
          {:server_entity_command, packet_data, entity_guid}
        )

        :ok

      {:error, reason} ->
        Logger.warning("[Visibility] Failed to serialize position update: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Send existing players to a newly joined player.

  When a player enters a zone, they need to see all existing players.
  This sends ServerEntityCreate for each existing player.

  NOTE: This is a placeholder - full implementation requires storing
  enough character data in the session to build ServerEntityCreate packets,
  or fetching character data from the database.
  """
  @spec send_existing_players_to(pid(), non_neg_integer(), non_neg_integer()) :: :ok
  def send_existing_players_to(_connection_pid, zone_id, instance_id) do
    # Get all sessions in this zone instance
    sessions = BezgelorWorld.WorldManager.get_zone_instance_sessions(zone_id, instance_id)

    Enum.each(sessions, fn session ->
      # Skip if no entity_guid (player not fully loaded)
      if session.entity_guid do
        # We need character data to build the entity packet
        # For now, just log - full implementation requires character lookup
        Logger.debug(
          "[Visibility] Would send existing player #{session.character_name} to connection"
        )

        # TODO: Fetch character data and send ServerEntityCreate
      end
    end)

    :ok
  end

  # Serialize a packet struct to binary using its Writable implementation
  defp serialize_packet(packet) do
    writer = PacketWriter.new()

    case packet.__struct__.write(packet, writer) do
      {:ok, writer} ->
        {:ok, PacketWriter.to_binary(writer)}

      error ->
        error
    end
  end
end
