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

  alias BezgelorDb.Achievements

  alias BezgelorProtocol.Packets.World.{
    ServerBuffApply,
    ServerBuffRemove,
    ServerEntityDeath,
    ServerLootDrop,
    ServerRespawn,
    ServerSpellEffect,
    ServerTelegraph,
    ServerXPGain
  }

  alias BezgelorProtocol.PacketWriter
  alias BezgelorWorld.{EventManager, WorldManager}

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
    # Get actual player XP state from character
    {current_xp, xp_to_level} = get_player_xp_state(player_guid)

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
  Broadcast a telegraph to players.

  Telegraphs are visual indicators showing where damage/effects will land.
  WildStar's action combat relies heavily on telegraphs for dodging.

  ## Parameters

  - `packet` - A ServerTelegraph struct
  - `recipient_guids` - List of player GUIDs to receive the telegraph
  """
  @spec broadcast_telegraph(ServerTelegraph.t(), [non_neg_integer()]) :: :ok
  def broadcast_telegraph(%ServerTelegraph{} = packet, recipient_guids) do
    writer = PacketWriter.new()
    {:ok, writer} = ServerTelegraph.write(packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    send_to_players(recipient_guids, :server_telegraph, packet_data)
  end

  @doc """
  Create and broadcast a circle telegraph.

  ## Parameters

  - `caster_guid` - Entity casting the ability
  - `position` - Center point {x, y, z}
  - `radius` - Circle radius
  - `duration` - How long to display in milliseconds
  - `color` - Telegraph color (:red, :blue, :yellow, :green)
  - `recipient_guids` - Players who should see the telegraph
  """
  @spec broadcast_circle_telegraph(
          non_neg_integer(),
          {float(), float(), float()},
          float(),
          non_neg_integer(),
          atom(),
          [non_neg_integer()]
        ) :: :ok
  def broadcast_circle_telegraph(caster_guid, position, radius, duration, color, recipient_guids) do
    packet = ServerTelegraph.circle(caster_guid, position, radius, duration, color)
    broadcast_telegraph(packet, recipient_guids)
  end

  @doc """
  Create and broadcast a cone telegraph.

  ## Parameters

  - `caster_guid` - Entity casting the ability
  - `position` - Cone origin point {x, y, z}
  - `angle` - Cone angle in degrees
  - `length` - Cone length from origin
  - `rotation` - Direction the cone faces (radians)
  - `duration` - How long to display in milliseconds
  - `color` - Telegraph color
  - `recipient_guids` - Players who should see the telegraph
  """
  @spec broadcast_cone_telegraph(
          non_neg_integer(),
          {float(), float(), float()},
          float(),
          float(),
          float(),
          non_neg_integer(),
          atom(),
          [non_neg_integer()]
        ) :: :ok
  def broadcast_cone_telegraph(
        caster_guid,
        position,
        angle,
        length,
        rotation,
        duration,
        color,
        recipient_guids
      ) do
    packet = ServerTelegraph.cone(caster_guid, position, angle, length, rotation, duration, color)
    broadcast_telegraph(packet, recipient_guids)
  end

  @doc """
  Broadcast telegraphs for a spell cast.

  Looks up telegraph data for the spell and broadcasts appropriate telegraph
  packets to nearby players. This integrates with the telegraph data extracted
  from TelegraphDamage.tbl and Spell4Telegraph.tbl.

  ## Parameters

  - `spell_id` - The spell being cast
  - `caster_guid` - Entity casting the spell
  - `position` - Caster position {x, y, z}
  - `rotation` - Caster rotation in radians
  - `recipient_guids` - Players who should see the telegraph

  ## Returns

  - `:ok` if telegraphs were broadcast (or none existed)
  """
  @spec broadcast_spell_telegraphs(
          non_neg_integer(),
          non_neg_integer(),
          {float(), float(), float()},
          float(),
          [non_neg_integer()]
        ) :: :ok
  def broadcast_spell_telegraphs(spell_id, caster_guid, position, rotation, recipient_guids) do
    telegraph_shapes = BezgelorData.Store.get_telegraph_shapes_for_spell(spell_id)

    Enum.each(telegraph_shapes, fn telegraph_data ->
      broadcast_telegraph_from_data(telegraph_data, caster_guid, spell_id, position, rotation, recipient_guids)
    end)

    :ok
  end

  # Convert telegraph_damage data to ServerTelegraph packet and broadcast
  defp broadcast_telegraph_from_data(telegraph_data, caster_guid, spell_id, position, rotation, recipient_guids) do
    shape = Map.get(telegraph_data, :damageShape, 0)
    duration_ms = Map.get(telegraph_data, :telegraphTimeEndMs, 1000) - Map.get(telegraph_data, :telegraphTimeStartMs, 0)
    duration = max(duration_ms, 500)  # Minimum 500ms display

    # Determine color - enemy spells are red, player spells are blue
    color = :blue  # Default to blue for player abilities

    packet = case shape do
      # Circle (0)
      0 ->
        radius = Map.get(telegraph_data, :param00, 5.0)
        ServerTelegraph.circle(caster_guid, position, radius, duration, color)

      # Ring/Donut (1)
      1 ->
        inner_radius = Map.get(telegraph_data, :param00, 2.0)
        outer_radius = Map.get(telegraph_data, :param01, 5.0)
        ServerTelegraph.donut(caster_guid, position, inner_radius, outer_radius, duration, color)

      # Square (2) - Map to rectangle
      2 ->
        width = Map.get(telegraph_data, :param00, 5.0)
        length = Map.get(telegraph_data, :param02, 5.0)
        %ServerTelegraph{
          caster_guid: caster_guid,
          spell_id: spell_id,
          shape: :rectangle,
          position: position,
          rotation: rotation,
          duration: duration,
          color: color,
          params: %{width: width, length: length}
        }

      # Cone (4) or LongCone (8)
      shape_id when shape_id in [4, 8] ->
        _start_radius = Map.get(telegraph_data, :param00, 0.0)
        end_radius = Map.get(telegraph_data, :param01, 10.0)
        angle = Map.get(telegraph_data, :param02, 90.0)
        # Use end_radius as length for cone (start_radius is offset from caster)
        ServerTelegraph.cone(caster_guid, position, angle, end_radius, rotation, duration, color)

      # Pie (5) - Map to donut with arc (simplified as circle)
      5 ->
        radius = Map.get(telegraph_data, :param01, 5.0)
        ServerTelegraph.circle(caster_guid, position, radius, duration, color)

      # Rectangle (7)
      7 ->
        width = Map.get(telegraph_data, :param00, 3.0)
        length = Map.get(telegraph_data, :param02, 10.0)
        %ServerTelegraph{
          caster_guid: caster_guid,
          spell_id: spell_id,
          shape: :rectangle,
          position: position,
          rotation: rotation,
          duration: duration,
          color: color,
          params: %{width: width, length: length}
        }

      # Unknown shape - default to circle
      _ ->
        radius = Map.get(telegraph_data, :param00, 5.0)
        ServerTelegraph.circle(caster_guid, position, radius, duration, color)
    end

    if packet do
      # Add spell_id to packet if not already set
      packet = if packet.spell_id, do: packet, else: %{packet | spell_id: spell_id}
      broadcast_telegraph(packet, recipient_guids)
    end
  end

  @doc """
  Notify EventManager and quest system of a creature kill.

  Called when a creature dies in combat. The EventManager will check if
  the creature type matches any active event objectives and update progress.
  Quest objectives for kill-type objectives are also updated.

  ## Single participant (legacy)
  """
  @spec notify_creature_kill(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def notify_creature_kill(zone_id, instance_id, killer_character_id, creature_id) do
    notify_creature_kill_multi(zone_id, instance_id, [killer_character_id], creature_id)
  end

  @doc """
  Notify EventManager and quest system of a creature kill with multiple participants.

  All participants receive kill credit for quest objectives.

  ## Parameters

  - `zone_id` - Zone where the kill occurred
  - `instance_id` - Instance where the kill occurred
  - `participant_character_ids` - List of character IDs that participated in the kill
  - `creature_id` - The creature that was killed

  ## Example

      # Notify all participants from creature death result
      notify_creature_kill_multi(zone_id, instance_id, result.participant_character_ids, creature_id)
  """
  @spec notify_creature_kill_multi(non_neg_integer(), non_neg_integer(), [non_neg_integer()], non_neg_integer()) :: :ok
  def notify_creature_kill_multi(zone_id, instance_id, participant_character_ids, creature_id) do
    # Notify EventManager (uses first participant as "killer" for event tracking)
    manager = EventManager.via_tuple(zone_id, instance_id)

    case GenServer.whereis(manager) do
      nil ->
        # No EventManager for this zone - normal for non-event zones
        :ok

      _pid ->
        # Notify the EventManager of the kill with first participant
        first_participant = List.first(participant_character_ids)
        if first_participant do
          EventManager.report_creature_kill(manager, first_participant, creature_id)
        end
    end

    # Send game event to ALL participants for session-based quest tracking
    # and broadcast kill achievement events
    for character_id <- participant_character_ids do
      send_game_event(character_id, :kill, %{creature_id: creature_id})

      # Achievement tracking for kill achievements
      Achievements.broadcast(character_id, {:kill, creature_id})
    end

    :ok
  end

  @doc """
  Notify quest system of item loot.

  Called when a player loots an item. Updates collect/loot quest objectives.
  """
  @spec notify_item_loot(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def notify_item_loot(character_id, item_id, count \\ 1) do
    # Send game event for each item looted
    Enum.each(1..count, fn _ ->
      send_game_event(character_id, :loot, %{item_id: item_id})
    end)
  end

  @doc """
  Notify quest system of object interaction.

  Called when a player interacts with a world object. Updates interact objectives.
  """
  @spec notify_object_interact(non_neg_integer(), non_neg_integer()) :: :ok
  def notify_object_interact(character_id, object_id) do
    send_game_event(character_id, :interact, %{object_id: object_id})
  end

  @doc """
  Notify quest system of NPC talk.

  Called when a player talks to an NPC. Updates talk objectives.
  """
  @spec notify_npc_talk(non_neg_integer(), non_neg_integer()) :: :ok
  def notify_npc_talk(character_id, creature_id) do
    send_game_event(character_id, :talk_npc, %{creature_id: creature_id})
  end

  @doc """
  Notify quest system of location/zone entry.

  Called when a player enters a tracked location. Updates enter/explore objectives.
  """
  @spec notify_location_enter(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def notify_location_enter(character_id, location_id, _zone_id) do
    send_game_event(character_id, :enter_location, %{location_id: location_id})
  end

  @doc """
  Notify quest system of item use.

  Called when a player uses an item. Updates use_item objectives.
  """
  @spec notify_item_use(non_neg_integer(), non_neg_integer()) :: :ok
  def notify_item_use(character_id, item_id) do
    send_game_event(character_id, :use_item, %{item_id: item_id})
  end

  @doc """
  Notify quest system of ability use.

  Called when a player uses a spell/ability. Updates use_ability objectives.
  """
  @spec notify_ability_use(non_neg_integer(), non_neg_integer()) :: :ok
  def notify_ability_use(character_id, spell_id) do
    send_game_event(character_id, :use_ability, %{spell_id: spell_id})
  end

  @doc """
  Notify quest system of resource gathering.

  Called when a player gathers a resource node. Updates gather objectives.
  """
  @spec notify_gather(non_neg_integer(), non_neg_integer(), atom() | nil) :: :ok
  def notify_gather(character_id, node_id, _resource_type \\ nil) do
    send_game_event(character_id, :gather, %{node_id: node_id})
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

  defp send_game_event(character_id, event_type, event_data) do
    case WorldManager.get_session_by_character(character_id) do
      nil ->
        :ok

      session ->
        send(session.connection_pid, {:game_event, event_type, event_data})
        :ok
    end
  end

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
                  # Broadcast level up achievement event
                  Achievements.broadcast(character_id, {:level_up, updated.level})
                  # TODO: Send level up packet

                {:error, reason} ->
                  Logger.error("Failed to persist XP: #{inspect(reason)}")
              end
          end
        end
    end
  end

  defp get_player_xp_state(player_guid) do
    alias BezgelorDb.Characters

    case WorldManager.get_session_by_entity_guid(player_guid) do
      nil ->
        {0, 1000}

      session ->
        if session.character_id do
          case Characters.get_character(session.character_id) do
            nil ->
              {0, 1000}

            character ->
              current = character.total_xp
              current_level_xp = Characters.total_xp_for_level(character.level)
              next_level_xp = Characters.total_xp_for_level(character.level + 1)
              xp_to_level = next_level_xp - current_level_xp
              {current - current_level_xp, xp_to_level}
          end
        else
          {0, 1000}
        end
    end
  end
end
