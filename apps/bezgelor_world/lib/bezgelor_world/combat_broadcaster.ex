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
    ServerBuffApply,
    ServerBuffRemove,
    ServerEntityDeath,
    ServerRespawn,
    ServerSpellEffect,
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
  Send spell effect (damage/heal) to recipient players.
  """
  @spec send_spell_effect(non_neg_integer(), non_neg_integer(), non_neg_integer(), map(), [non_neg_integer()]) :: :ok
  def send_spell_effect(caster_guid, target_guid, spell_id, effect, recipient_guids) do
    packet = case effect.type do
      :damage ->
        ServerSpellEffect.damage(caster_guid, target_guid, spell_id, effect.amount, Map.get(effect, :is_crit, false))

      :heal ->
        ServerSpellEffect.heal(caster_guid, target_guid, spell_id, effect.amount, Map.get(effect, :is_crit, false))

      :buff ->
        ServerSpellEffect.buff(caster_guid, target_guid, spell_id, effect.amount)

      _ ->
        ServerSpellEffect.damage(caster_guid, target_guid, spell_id, effect.amount, false)
    end

    writer = PacketWriter.new()
    {:ok, writer} = ServerSpellEffect.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    send_to_players(recipient_guids, :server_spell_effect, packet_data)
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

  @doc """
  Send respawn notification to a player.
  """
  @spec send_respawn(non_neg_integer(), {float(), float(), float()}, non_neg_integer(), non_neg_integer(), [non_neg_integer()]) :: :ok
  def send_respawn(entity_guid, {x, y, z}, health, max_health, recipient_guids) do
    packet = %ServerRespawn{
      entity_guid: entity_guid,
      position_x: x,
      position_y: y,
      position_z: z,
      health: health,
      max_health: max_health
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerRespawn.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    send_to_players(recipient_guids, :server_respawn, packet_data)
  end

  @doc """
  Broadcast buff application to a list of player GUIDs.
  """
  @spec broadcast_buff_apply(non_neg_integer(), non_neg_integer(), BezgelorCore.BuffDebuff.t(), [non_neg_integer()]) :: :ok
  def broadcast_buff_apply(target_guid, caster_guid, buff, recipient_guids) do
    packet = ServerBuffApply.new(
      target_guid,
      caster_guid,
      buff.id,
      buff.spell_id,
      buff.buff_type,
      buff.amount,
      buff.duration,
      buff.is_debuff
    )

    writer = PacketWriter.new()
    {:ok, writer} = ServerBuffApply.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    send_to_players(recipient_guids, :server_buff_apply, packet_data)
  end

  @doc """
  Broadcast buff removal to a list of player GUIDs.
  """
  @spec broadcast_buff_remove(non_neg_integer(), non_neg_integer(), atom(), [non_neg_integer()]) :: :ok
  def broadcast_buff_remove(target_guid, buff_id, reason, recipient_guids) do
    packet = ServerBuffRemove.new(target_guid, buff_id, reason)

    writer = PacketWriter.new()
    {:ok, writer} = ServerBuffRemove.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    send_to_players(recipient_guids, :server_buff_remove, packet_data)
  end

  @doc """
  Send buff apply notification to target player.
  """
  @spec send_buff_apply(non_neg_integer(), non_neg_integer(), BezgelorCore.BuffDebuff.t()) :: :ok
  def send_buff_apply(target_guid, caster_guid, buff) do
    broadcast_buff_apply(target_guid, caster_guid, buff, [target_guid])
  end

  @doc """
  Send buff removal notification to target player.
  """
  @spec send_buff_remove(non_neg_integer(), non_neg_integer(), atom()) :: :ok
  def send_buff_remove(target_guid, buff_id, reason) do
    broadcast_buff_remove(target_guid, buff_id, reason, [target_guid])
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
