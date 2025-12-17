defmodule BezgelorProtocol.Handler.ResurrectionHandler do
  @moduledoc """
  Handler for resurrection-related packets.

  Handles player responses to resurrection offers and bindpoint respawn requests.

  ## Flow

  1. Parse resurrection packet
  2. Validate player is dead with pending offer
  3. Process accept/decline through DeathManager
  4. Return ServerResurrect packet to confirm resurrection
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.PacketWriter
  alias BezgelorProtocol.Packets.World.{
    ClientResurrectAccept,
    ServerResurrect
  }
  alias BezgelorWorld.{CombatBroadcaster, DeathManager}

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)
    opcode = state.current_opcode

    case opcode do
      :client_resurrect_accept -> handle_accept(reader, state)
      :client_resurrect_at_bindpoint -> handle_bindpoint(reader, state)
      _ -> {:error, :unknown_resurrect_opcode}
    end
  end

  defp handle_accept(reader, state) do
    entity_guid = state.session_data[:entity_guid]

    with {:ok, packet, _reader} <- ClientResurrectAccept.read(reader) do
      if packet.accept do
        process_accept(entity_guid, state)
      else
        process_decline(entity_guid, state)
      end
    else
      {:error, reason} ->
        Logger.warning("Failed to read resurrect accept packet: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_bindpoint(_reader, state) do
    entity_guid = state.session_data[:entity_guid]
    process_bindpoint_respawn(entity_guid, state)
  end

  defp process_accept(entity_guid, state) do
    zone_id = state.session_data[:zone_id]

    case DeathManager.accept_resurrection(entity_guid) do
      {:ok, result} ->
        {x, y, z} = result.position
        health_percent = result.health_percent

        # Broadcast resurrection to nearby players
        broadcast_resurrection(entity_guid, {x, y, z}, health_percent, state)

        res_packet = ServerResurrect.new(:spell, zone_id, {x, y, z}, health_percent)
        {opcode, payload} = serialize_packet(res_packet)

        Logger.info("Player #{entity_guid} accepted resurrection")
        {:reply_world_encrypted, opcode, payload, state}

      {:error, :not_dead} ->
        Logger.warning("Player #{entity_guid} tried to accept resurrection but is not dead")
        {:error, :not_dead}

      {:error, :no_offer} ->
        Logger.warning("Player #{entity_guid} tried to accept resurrection but no offer pending")
        {:error, :no_offer}
    end
  end

  defp process_decline(entity_guid, state) do
    DeathManager.decline_resurrection(entity_guid)
    Logger.debug("Player #{entity_guid} declined resurrection")
    {:ok, state}
  end

  defp process_bindpoint_respawn(entity_guid, state) do
    case DeathManager.respawn_at_bindpoint(entity_guid) do
      {:ok, result} ->
        {x, y, z} = result.position
        zone_id = result.zone_id
        health_percent = result.health_percent

        # Apply death penalty (durability loss) when respawning at bindpoint
        apply_death_penalty(state)

        # Broadcast resurrection to nearby players (at bindpoint location)
        broadcast_resurrection(entity_guid, {x, y, z}, health_percent, state)

        res_packet = ServerResurrect.new(:bindpoint, zone_id, {x, y, z}, health_percent)
        {opcode, payload} = serialize_packet(res_packet)

        Logger.info("Player #{entity_guid} respawned at bindpoint in zone #{zone_id}")
        {:reply_world_encrypted, opcode, payload, state}

      {:error, :not_dead} ->
        Logger.warning("Player #{entity_guid} tried to respawn at bindpoint but is not dead")
        {:error, :not_dead}
    end
  end

  # Apply death penalties such as durability loss
  defp apply_death_penalty(state) do
    character = state.session_data[:character]

    if character do
      level = character.level || 1
      character_id = character.id

      case BezgelorDb.Inventory.apply_death_durability_loss(character_id, level) do
        {:ok, count} when count > 0 ->
          Logger.debug("Applied durability loss to #{count} items for character #{character_id}")

        {:ok, 0} ->
          Logger.debug("No durability loss applied (level #{level})")

        {:error, reason} ->
          Logger.warning("Failed to apply durability loss: #{inspect(reason)}")
      end
    end
  end

  # Broadcast resurrection to nearby players
  defp broadcast_resurrection(entity_guid, position, health_percent, state) do
    zone_id = state.session_data[:zone_id]
    character = state.session_data[:character]

    if zone_id && character do
      # Calculate actual health from percentage
      max_health = character.base_health || 10000
      health = round(max_health * health_percent / 100.0)

      # Get nearby players in the zone
      alias BezgelorWorld.WorldManager
      nearby_guids = WorldManager.get_nearby_player_guids(zone_id, position, 100.0)

      # Exclude the player who just resurrected
      recipient_guids = Enum.reject(nearby_guids, &(&1 == entity_guid))

      if recipient_guids != [] do
        CombatBroadcaster.broadcast_player_resurrection(
          entity_guid,
          position,
          health,
          max_health,
          recipient_guids
        )
      end
    end
  end

  # Serialize a packet struct to {opcode, binary_payload}
  defp serialize_packet(packet) do
    opcode = packet.__struct__.opcode()
    writer = PacketWriter.new()
    {:ok, writer} = packet.__struct__.write(packet, writer)
    payload = PacketWriter.to_binary(writer)
    {opcode, payload}
  end
end
