defmodule BezgelorWorld.Handler.CombatHandler do
  @moduledoc """
  Handler for targeting and respawn packets.

  ## Overview

  Processes combat-related client requests:
  - Setting/clearing targets
  - Player respawn requests

  ## Packets Handled

  - ClientSetTarget (0x0500)
  - ClientRespawn (0x0511)
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{
    ClientSetTarget,
    ClientRespawn,
    ServerTargetUpdate,
    ServerRespawn
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorCore.Entity
  alias BezgelorWorld.{CombatBroadcaster, CreatureManager}
  alias BezgelorWorld.Zone.Instance, as: ZoneInstance

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    # Try to read as SetTarget first, then Respawn
    with {:error, _} <- handle_set_target(reader, state),
         {:error, _} <- handle_respawn(reader, state) do
      Logger.warning("CombatHandler: Unknown packet format")
      {:error, :unknown_packet}
    end
  end

  defp handle_set_target(reader, state) do
    case ClientSetTarget.read(reader) do
      {:ok, packet, _reader} ->
        process_set_target(packet, state)

      {:error, _reason} ->
        {:error, :not_set_target}
    end
  end

  defp handle_respawn(reader, state) do
    case ClientRespawn.read(reader) do
      {:ok, packet, _reader} ->
        process_respawn(packet, state)

      {:error, _reason} ->
        {:error, :not_respawn}
    end
  end

  defp process_set_target(packet, state) do
    unless state.session_data[:in_world] do
      Logger.warning("SetTarget received before player entered world")
      {:error, :not_in_world}
    else
      target_guid = packet.target_guid
      entity_guid = state.session_data[:entity_guid]

      # Validate target if not clearing
      if target_guid != 0 do
        # Check if target is a valid creature
        if CreatureManager.creature_targetable?(target_guid) do
          Logger.debug("Player #{entity_guid} targeting creature #{target_guid}")
          send_target_update(entity_guid, target_guid, state)
        else
          # Could be targeting another player - for now just echo back
          Logger.debug("Player #{entity_guid} targeting entity #{target_guid}")
          send_target_update(entity_guid, target_guid, state)
        end
      else
        # Clear target
        Logger.debug("Player #{entity_guid} clearing target")
        send_target_update(entity_guid, 0, state)
      end
    end
  end

  defp process_respawn(packet, state) do
    unless state.session_data[:in_world] do
      Logger.warning("Respawn received before player entered world")
      {:error, :not_in_world}
    else
      entity_guid = state.session_data[:entity_guid]
      zone_id = state.session_data[:zone_id] || 1
      instance_id = 1

      # Get current player entity from zone
      case ZoneInstance.get_entity({zone_id, instance_id}, entity_guid) do
        {:ok, entity} when entity.health == 0 ->
          Logger.info("Player #{entity_guid} respawning (type: #{packet.respawn_type})")

          # Restore health in zone instance
          :ok =
            ZoneInstance.update_entity({zone_id, instance_id}, entity_guid, fn e ->
              Entity.respawn(e)
            end)

          # Get updated entity for position
          {:ok, respawned_entity} = ZoneInstance.get_entity({zone_id, instance_id}, entity_guid)
          {x, y, z} = respawned_entity.position

          # Broadcast respawn to player (and nearby players in future)
          CombatBroadcaster.send_respawn(
            entity_guid,
            {x, y, z},
            respawned_entity.health,
            respawned_entity.max_health,
            [entity_guid]
          )

          {:ok, state}

        {:ok, _entity} ->
          Logger.warning("Respawn requested but player not dead")
          {:error, :not_dead}

        :error ->
          Logger.warning("Respawn requested but player not in zone")
          {:error, :not_in_zone}
      end
    end
  end

  defp send_target_update(entity_guid, target_guid, state) do
    target_packet = %ServerTargetUpdate{
      entity_guid: entity_guid,
      target_guid: target_guid
    }

    send_packet(:server_target_update, target_packet, state)
  end

  defp send_packet(opcode, packet, state) do
    writer = PacketWriter.new()

    {:ok, writer} =
      case opcode do
        :server_target_update -> ServerTargetUpdate.write(packet, writer)
        :server_respawn -> ServerRespawn.write(packet, writer)
      end

    packet_data = PacketWriter.to_binary(writer)
    {:reply, opcode, packet_data, state}
  end
end
