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
    ServerLootDrop,
    ServerRespawn,
    ServerSpellEffect,
    ServerXPGain
  }

  alias BezgelorProtocol.PacketWriter
  alias BezgelorWorld.{EventManager, WorldManager}
  alias BezgelorWorld.Quest.ObjectiveHandler

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
    xp_amount = Map.get(rewards, :xp_reward, 0)

    # Send XP if any
    if xp_amount > 0 do
      # Persist XP to database
      persist_xp_gain(player_guid, xp_amount)

      # Send XP gain packet to client
      send_xp_gain(player_guid, xp_amount, :kill, creature_guid)
    end

    # Send loot notification
    gold = Map.get(rewards, :gold, 0)
    items = Map.get(rewards, :items, [])

    if gold > 0 or length(items) > 0 do
      send_loot_drop(player_guid, creature_guid, gold, items)
    end

    :ok
  end

  @doc """
  Send loot drop notification to a player.
  """
  @spec send_loot_drop(non_neg_integer(), non_neg_integer(), non_neg_integer(), [{non_neg_integer(), non_neg_integer()}]) :: :ok
  def send_loot_drop(player_guid, source_guid, gold, items) do
    packet = %ServerLootDrop{
      source_guid: source_guid,
      gold: gold,
      items: items
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerLootDrop.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    send_to_player(player_guid, :server_loot_drop, packet_data)

    Logger.debug("Sent loot drop to player #{player_guid}: #{gold} gold, #{length(items)} items")
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

  @doc """
  Notify EventManager and quest system of a creature kill.

  Called when a creature dies in combat. The EventManager will check if
  the creature type matches any active event objectives and update progress.
  Quest objectives for kill-type objectives are also updated.
  """
  @spec notify_creature_kill(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def notify_creature_kill(zone_id, instance_id, killer_character_id, creature_id) do
    # Notify EventManager
    manager = EventManager.via_tuple(zone_id, instance_id)

    case GenServer.whereis(manager) do
      nil ->
        # No EventManager for this zone - normal for non-event zones
        :ok

      _pid ->
        # Notify the EventManager of the kill
        EventManager.report_creature_kill(manager, killer_character_id, creature_id)
    end

    # Notify quest objective handler
    case WorldManager.get_session_by_character(killer_character_id) do
      nil ->
        :ok

      session ->
        ObjectiveHandler.process_event(
          :kill,
          session.connection_pid,
          killer_character_id,
          %{creature_id: creature_id}
        )
    end
  end

  @doc """
  Notify quest system of item loot.

  Called when a player loots an item. Updates collect/loot quest objectives.
  """
  @spec notify_item_loot(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def notify_item_loot(character_id, item_id, count \\ 1) do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        :ok

      session ->
        ObjectiveHandler.process_event(
          :loot,
          session.connection_pid,
          character_id,
          %{item_id: item_id, count: count}
        )
    end
  end

  @doc """
  Notify quest system of object interaction.

  Called when a player interacts with a world object. Updates interact objectives.
  """
  @spec notify_object_interact(non_neg_integer(), non_neg_integer()) :: :ok
  def notify_object_interact(character_id, object_id) do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        :ok

      session ->
        ObjectiveHandler.process_event(
          :interact,
          session.connection_pid,
          character_id,
          %{object_id: object_id}
        )
    end
  end

  @doc """
  Notify quest system of NPC talk.

  Called when a player talks to an NPC. Updates talk objectives.
  """
  @spec notify_npc_talk(non_neg_integer(), non_neg_integer()) :: :ok
  def notify_npc_talk(character_id, creature_id) do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        :ok

      session ->
        ObjectiveHandler.process_event(
          :talk_npc,
          session.connection_pid,
          character_id,
          %{creature_id: creature_id}
        )
    end
  end

  @doc """
  Notify quest system of location/zone entry.

  Called when a player enters a tracked location. Updates enter/explore objectives.
  """
  @spec notify_location_enter(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def notify_location_enter(character_id, location_id, zone_id) do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        :ok

      session ->
        # Try both location_id and zone_id for objective matching
        ObjectiveHandler.process_event(
          :enter_location,
          session.connection_pid,
          character_id,
          %{location_id: location_id, zone_id: zone_id}
        )
    end
  end

  @doc """
  Notify quest system of item use.

  Called when a player uses an item. Updates use_item objectives.
  """
  @spec notify_item_use(non_neg_integer(), non_neg_integer()) :: :ok
  def notify_item_use(character_id, item_id) do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        :ok

      session ->
        ObjectiveHandler.process_event(
          :use_item,
          session.connection_pid,
          character_id,
          %{item_id: item_id}
        )
    end
  end

  @doc """
  Notify quest system of ability use.

  Called when a player uses a spell/ability. Updates use_ability objectives.
  """
  @spec notify_ability_use(non_neg_integer(), non_neg_integer()) :: :ok
  def notify_ability_use(character_id, spell_id) do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        :ok

      session ->
        ObjectiveHandler.process_event(
          :use_ability,
          session.connection_pid,
          character_id,
          %{spell_id: spell_id}
        )
    end
  end

  @doc """
  Notify quest system of resource gathering.

  Called when a player gathers a resource node. Updates gather objectives.
  """
  @spec notify_gather(non_neg_integer(), non_neg_integer(), atom() | nil) :: :ok
  def notify_gather(character_id, node_id, resource_type \\ nil) do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        :ok

      session ->
        ObjectiveHandler.process_event(
          :gather,
          session.connection_pid,
          character_id,
          %{node_id: node_id, resource_type: resource_type}
        )
    end
  end

  @doc """
  Notify EventManager of damage dealt to a world boss.

  Tracks damage contribution for boss fights.
  """
  @spec notify_boss_damage(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def notify_boss_damage(zone_id, instance_id, character_id, boss_id, damage_amount) do
    manager = EventManager.via_tuple(zone_id, instance_id)

    case GenServer.whereis(manager) do
      nil ->
        :ok

      _pid ->
        EventManager.record_boss_damage(manager, boss_id, character_id, damage_amount)
    end
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

  defp persist_xp_gain(player_guid, xp_amount) do
    alias BezgelorDb.Characters

    # Get character_id from session
    case WorldManager.get_session_by_entity_guid(player_guid) do
      nil ->
        Logger.warning("Cannot persist XP: no session for player #{player_guid}")

      session ->
        character_id = session.character_id

        if character_id do
          case Characters.get_character(character_id) do
            nil ->
              Logger.warning("Cannot persist XP: character #{character_id} not found")

            character ->
              case Characters.add_experience(character, xp_amount) do
                {:ok, _updated} ->
                  Logger.debug("Persisted #{xp_amount} XP for character #{character_id}")

                {:ok, updated, level_up: true} ->
                  Logger.info("Character #{character_id} leveled up to #{updated.level}!")
                  # TODO: Send level up packet

                {:error, reason} ->
                  Logger.error("Failed to persist XP: #{inspect(reason)}")
              end
          end
        end
    end
  end
end
