defmodule BezgelorWorld.CombatBroadcaster do
  @moduledoc """
  Broadcasts combat events to players.

  Handles construction and delivery of combat-related packets:
  - Entity death notifications
  - XP gain notifications
  - Damage/healing effects
  - Loot notifications
  """

  require Logger

  alias BezgelorProtocol.Packets.World.{
    ServerEntityDeath,
    ServerXPGain
  }

  alias BezgelorProtocol.PacketWriter
  alias BezgelorWorld.WorldManager

  @doc """
  Broadcast entity death to a list of player GUIDs.
  """
  @spec broadcast_entity_death(non_neg_integer(), non_neg_integer(), [non_neg_integer()]) :: :ok
  def broadcast_entity_death(entity_guid, killer_guid, recipient_guids) do
    packet = %ServerEntityDeath{
      entity_guid: entity_guid,
      killer_guid: killer_guid
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerEntityDeath.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    send_to_players(recipient_guids, :server_entity_death, packet_data)
  end

  @doc """
  Send XP gain notification to a player.
  """
  @spec send_xp_gain(non_neg_integer(), non_neg_integer(), atom(), non_neg_integer()) :: :ok
  def send_xp_gain(player_guid, xp_amount, source_type, source_guid) do
    # TODO: Get actual player XP state from database/cache
    current_xp = 0
    xp_to_level = 1000

    packet = %ServerXPGain{
      xp_amount: xp_amount,
      source_type: source_type,
      source_guid: source_guid,
      current_xp: current_xp + xp_amount,
      xp_to_level: xp_to_level
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerXPGain.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    send_to_player(player_guid, :server_xp_gain, packet_data)
  end

  @doc """
  Notify player of creature kill rewards (XP and loot).
  """
  @spec send_kill_rewards(non_neg_integer(), non_neg_integer(), map()) :: :ok
  def send_kill_rewards(player_guid, creature_guid, rewards) do
    # Send XP if any
    if Map.get(rewards, :xp_reward, 0) > 0 do
      send_xp_gain(player_guid, rewards.xp_reward, :kill, creature_guid)
    end

    # TODO: Send loot notification when loot system is implemented
    items = Map.get(rewards, :items, [])

    if length(items) > 0 do
      Logger.debug("Loot dropped for player #{player_guid}: #{inspect(items)}")
    end

    :ok
  end

  # Private helpers

  defp send_to_player(player_guid, opcode, packet_data) do
    case find_connection_for_guid(player_guid) do
      nil ->
        Logger.warning("No connection found for player #{player_guid}")

      connection_pid ->
        send(connection_pid, {:send_packet, opcode, packet_data})
    end

    :ok
  end

  defp send_to_players(guids, opcode, packet_data) do
    Enum.each(guids, fn guid ->
      send_to_player(guid, opcode, packet_data)
    end)

    :ok
  end

  defp find_connection_for_guid(player_guid) do
    sessions = WorldManager.list_sessions()

    case Enum.find(sessions, fn {_account_id, session} ->
           session.entity_guid == player_guid
         end) do
      nil -> nil
      {_account_id, session} -> session.connection_pid
    end
  end
end
