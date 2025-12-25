defmodule BezgelorWorld.Handler.SpellHandler do
  @moduledoc """
  Handler for spell casting packets.

  ## Overview

  Processes ClientCastSpell and ClientCancelCast packets.
  Validates cast requests, manages cast state, and sends
  appropriate response packets.

  ## Flow

  1. Parse cast request
  2. Validate player is in world
  3. Validate spell and target
  4. Check cooldowns
  5. Start cast or apply instant spell
  6. Send result packets
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorProtocol.Packets.World.{
    ClientCastSpell,
    ClientCancelCast,
    ServerEntityCommand,
    ServerSpellStart,
    ServerSpellGo,
    ServerSpellFinish,
    ServerSpellEffect,
    ServerCastResult,
    ServerCooldown,
    ServerResurrectOffer
  }

  # Spellslinger Gate spell ID (Spell4 ID)
  # NOTE: Gate teleport (ForcedMove effect) is NOT WORKING - see GitHub issue #48
  # The spell visual plays but the player doesn't move. NexusForever never
  # implemented ForcedMove (effect type 0x0003) either.
  @gate_spell_id 34355
  # Gate teleport distance (from telegraph 142 param01)
  @gate_teleport_distance 30.0

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorCore.{Spell, BuffDebuff}

  alias BezgelorWorld.{
    BuffManager,
    CombatBroadcaster,
    DeathManager,
    SpellManager
  }

  alias BezgelorWorld.World.Instance, as: WorldInstance

  import Bitwise

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    # Try to parse as cast spell first, then cancel
    case ClientCastSpell.read(reader) do
      {:ok, packet, _reader} ->
        handle_cast_request(packet, state)

      {:error, _reason} ->
        # ClientCancelCast.read always succeeds since it's an empty packet
        {:ok, _packet, _reader} = ClientCancelCast.read(reader)
        handle_cancel_cast(state)
    end
  end

  @doc """
  Handle a parsed cast request packet.
  """
  @spec handle_cast_request(ClientCastSpell.t(), map()) :: term()
  def handle_cast_request(packet, state) do
    unless state.session_data[:in_world] do
      Logger.warning("Spell cast received before player entered world")
      {:error, :not_in_world}
    else
      process_cast(packet, state)
    end
  end

  defp process_cast(packet, state) do
    player_guid = state.session_data[:entity_guid]
    character = state.session_data[:character]

    # Look up the spell ID from the character's ability inventory using bag_index
    # This matches NexusForever: Inventory.GetItem(InventoryLocation.Ability, bagIndex)
    spell_id = resolve_spell_from_bag(packet.bag_index, state)

    if spell_id == nil do
      Logger.warning(
        "[SpellHandler] No ability at bag_index #{packet.bag_index} for character #{character && character.id}"
      )

      send_cast_result(:failed, :not_known, 0, state)
    else
      spell = Spell.get(spell_id)

      # Get target from player's current target state (stored in session_data)
      target_guid = state.session_data[:target_guid] || 0
      target_position = state.session_data[:position] || {0.0, 0.0, 0.0}

      # Create a normalized packet struct for the rest of the handler
      normalized_packet = %{
        spell_id: spell_id,
        target_guid: target_guid,
        target_position: target_position,
        client_unique_id: packet.client_unique_id,
        button_pressed: packet.button_pressed
      }

      cond do
        spell == nil ->
          Logger.warning("[SpellHandler] Unknown spell_id #{spell_id}")
          send_cast_result(:failed, :not_known, spell_id, state)

        not validate_target(spell, normalized_packet, state) ->
          send_cast_result(:failed, :invalid_target, spell_id, state)

        not validate_range(spell, normalized_packet, state) ->
          send_cast_result(:failed, :out_of_range, spell_id, state)

        true ->
          do_cast(spell, normalized_packet, player_guid, state)
      end
    end
  end

  # Resolve spell ID from action set shortcuts.
  # The client sends bag_index which corresponds to a slot in the action set.
  # We use shortcuts because they store both:
  #   - object_id = Spell4Base ID (for display/icons)
  #   - spell_id = Spell4 ID (for casting/effects)
  # Ability items use Spell4Base IDs for icon display, but we need Spell4 ID for casting.
  defp resolve_spell_from_bag(bag_index, state) do
    character = state.session_data[:character]
    active_spec = (character && character.active_spec) || 0

    # Always use shortcuts for spell_id lookup since they have the correct Spell4 ID
    resolve_from_shortcuts(bag_index, active_spec, state)
  end

  # Look up from action_set_shortcuts
  defp resolve_from_shortcuts(bag_index, active_spec, state) do
    shortcuts = state.session_data[:action_set_shortcuts] || []

    shortcut =
      Enum.find(shortcuts, fn s ->
        s.slot == bag_index and s.spec_index == active_spec
      end)

    shortcut && shortcut.spell_id
  end

  defp do_cast(spell, packet, player_guid, state) do
    # Get caster stats from character data and buff modifiers
    caster_stats = get_caster_stats(state)

    case SpellManager.cast_spell(
           player_guid,
           spell.id,
           packet.target_guid,
           packet.target_position,
           caster_stats
         ) do
      {:ok, :instant, result} ->
        handle_instant_cast(spell, packet, player_guid, result, state)

      {:ok, :casting, cast_time} ->
        handle_cast_start(spell, packet, player_guid, cast_time, state)

      {:error, :cooldown} ->
        send_cast_result(:failed, :cooldown, spell.id, state)

      {:error, :already_casting} ->
        send_cast_result(:failed, :already_casting, spell.id, state)

      {:error, reason} ->
        send_cast_result(:failed, reason, spell.id, state)
    end
  end

  defp handle_instant_cast(spell, _packet, player_guid, result, state) do
    # Get caster info from session
    position = state.session_data[:position] || {0.0, 0.0, 0.0}
    yaw = state.session_data[:yaw] || 0.0
    # Entity ID is the low 32 bits of the GUID
    caster_id = player_guid &&& 0xFFFFFFFF

    # Generate unique casting ID (simple incrementing counter)
    casting_id = :erlang.unique_integer([:positive, :monotonic]) &&& 0xFFFFFFFF

    # Calculate destination for Gate teleport
    # NOTE: This destination calculation works, but the actual teleport doesn't.
    # See build_teleport_command/2 for details on what we've tried.
    destination =
      if spell.id == @gate_spell_id do
        calculate_gate_destination(position, yaw)
      else
        position
      end

    # Build telegraph position data for Gate
    # Tried: Including telegraph data in spell packets to hint at teleport destination
    # Result: No effect on player movement
    start_telegraph_positions =
      if spell.id == @gate_spell_id do
        [
          %{
            telegraph_id: 142,
            attached_unit_id: caster_id,
            target_flags: 3,
            position: destination,
            yaw: yaw,
            pitch: 0.0
          }
        ]
      else
        []
      end

    # Build and send ServerSpellStart
    spell_start = ServerSpellStart.new(
      casting_id: casting_id,
      spell4_id: spell.id,
      caster_id: caster_id,
      primary_target_id: caster_id,
      position: position,
      yaw: yaw,
      user_initiated: true,
      telegraph_positions: start_telegraph_positions
    )

    # Build ServerSpellGo - set primary_destination to teleport target for Gate
    # For Gate, include telegraph position at the destination
    telegraph_positions =
      if spell.id == @gate_spell_id do
        [
          %{
            # Gate telegraph ID
            telegraph_id: 142,
            attached_unit_id: caster_id,
            target_flags: 3,
            position: destination,
            yaw: yaw,
            pitch: 0.0
          }
        ]
      else
        []
      end

    spell_go = ServerSpellGo.new(
      casting_id: casting_id,
      caster_id: caster_id,
      position: position,
      yaw: yaw,
      destination: destination,
      telegraph_positions: telegraph_positions
    )

    # Get world context for creature damage
    world_id = state.session_data[:world_id] || 1
    instance_id = 1
    world_key = {world_id, instance_id}

    # Apply effects to targets and collect kill info
    {_effect_packets, kill_info} =
      apply_spell_effects(player_guid, player_guid, spell, result.effects, world_key)

    # Broadcast kill rewards if creature was killed
    if kill_info do
      zone_id = state.session_data[:zone_id] || 1
      instance_id = state.session_data[:zone_instance_id] || 1
      participant_ids = kill_info.rewards[:participant_character_ids] || []

      CombatBroadcaster.broadcast_entity_death(
        kill_info.creature_guid,
        player_guid,
        [player_guid]
      )

      CombatBroadcaster.send_kill_rewards(
        player_guid,
        kill_info.creature_guid,
        kill_info.rewards
      )

      if participant_ids != [] do
        CombatBroadcaster.notify_creature_kill_multi(
          zone_id,
          instance_id,
          participant_ids,
          kill_info.rewards.creature_id
        )
      end

      Logger.info(
        "Creature #{kill_info.creature_guid} killed by #{player_guid}! XP: #{kill_info.rewards.xp_reward}"
      )
    end

    # Apply ForcedMove effect for Gate teleport - update server-side position
    # NOTE: We update server state even though client teleport doesn't work,
    # so if/when teleport is fixed, server position will be correct.
    state =
      if spell.id == @gate_spell_id do
        new_session_data = Map.put(state.session_data, :position, destination)
        %{state | session_data: new_session_data}
      else
        state
      end

    # For Gate, attempt to send teleport command (currently non-functional)
    # See build_teleport_command/2 for documentation of failed approaches
    if spell.id == @gate_spell_id do
      teleport_packets = build_teleport_command(player_guid, destination)
      send_spell_start_go_and_extra(spell_start, spell_go, teleport_packets, state)
    else
      send_spell_start_go_and_extra(spell_start, spell_go, [], state)
    end
  end

  # Calculate Gate teleport destination based on yaw (facing direction)
  # Yaw is in radians, 0 = facing positive X, increases counter-clockwise
  defp calculate_gate_destination({x, y, z}, yaw) do
    dx = @gate_teleport_distance * :math.cos(yaw)
    dz = @gate_teleport_distance * :math.sin(yaw)
    {x + dx, y, z + dz}
  end

  # Build ServerEntityCommand packet to teleport the player
  #
  # WARNING: This does NOT work. The packet is sent but the client ignores it.
  # See GitHub issue #48 for tracking.
  #
  # Approaches tried (all failed):
  #
  # 1. ServerEntityCommand with set_position, server_controlled: true
  #    Result: Client ignores - players control their own movement
  #
  # 2. ServerEntityCommand with set_position, server_controlled: false
  #    Result: No effect
  #
  # 3. ServerEntityCommand with set_position_path (current approach)
  #    Result: No effect - this works for NPCs but not players
  #
  # 4. Setting primary_destination in ServerSpellGo to teleport target
  #    Result: No effect on player position
  #
  # 5. Including telegraph position data in spell packets
  #    Result: No effect
  #
  # 6. Sending entity command before vs after spell packets
  #    Result: No difference
  #
  # 7. Various time_reset and blend combinations
  #    Result: No effect
  #
  # The WildStar client appears to handle ForcedMove effects entirely client-side
  # based on spell effect data, or there's a different packet/mechanism needed.
  # NexusForever never implemented ForcedMove (effect type 0x0003).
  #
  defp build_teleport_command(player_guid, destination) do
    # Use full GUID, truncated to uint32
    entity_id = player_guid &&& 0xFFFFFFFF

    teleport_command = %ServerEntityCommand{
      guid: entity_id,
      time: System.system_time(:millisecond) &&& 0xFFFFFFFF,
      time_reset: true,
      server_controlled: true,
      commands: [
        # Using set_position_path with high speed for "instant" movement
        # This works for NPC movement but not for player self-teleportation
        %{
          type: :set_position_path,
          positions: [destination],
          speed: 1000.0,
          spline_type: :linear,
          spline_mode: :one_shot,
          offset: 0,
          blend: false
        }
      ]
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerEntityCommand.write(teleport_command, writer)
    teleport_data = PacketWriter.to_binary(writer)

    [{:server_entity_command, teleport_data}]
  end

  # Apply spell effects to targets, calling World.Instance for damage to creatures
  # and BuffManager for buff/debuff effects
  defp apply_spell_effects(caster_guid, target_guid, spell, effects, world_key) do
    Enum.reduce(effects, {[], nil}, fn effect, {packets, kill_info} ->
      target = if spell.target_type == :self, do: caster_guid, else: target_guid
      packet = build_effect_packet(caster_guid, target, spell.id, effect)

      # Apply damage effects to creatures
      new_kill_info =
        if effect.type == :damage and is_creature_guid?(target) do
          apply_damage_to_creature(world_key, target, caster_guid, effect.amount)
        else
          nil
        end

      # Apply buff/debuff effects via BuffManager
      apply_buff_effect(caster_guid, target, spell, effect)

      {[packet | packets], new_kill_info || kill_info}
    end)
    |> then(fn {packets, kill_info} -> {Enum.reverse(packets), kill_info} end)
  end

  # Apply buff or debuff effect via BuffManager
  defp apply_buff_effect(caster_guid, target_guid, spell, effect) do
    case effect.type do
      :buff ->
        apply_buff(caster_guid, target_guid, spell, effect, false)

      :debuff ->
        apply_buff(caster_guid, target_guid, spell, effect, true)

      :hot ->
        # HoT is a beneficial periodic effect
        apply_periodic_buff(caster_guid, target_guid, spell, effect, false)

      :dot ->
        # DoT is a harmful periodic effect
        apply_periodic_buff(caster_guid, target_guid, spell, effect, true)

      :resurrect ->
        # Resurrection effect - offer resurrection to dead target
        apply_resurrect_effect(caster_guid, target_guid, spell, effect)

      _ ->
        :ok
    end
  end

  defp apply_buff(caster_guid, target_guid, spell, effect, is_debuff) do
    # Get buff_type and duration from original spell effect (result effect doesn't have these)
    original_effect = Enum.find(spell.effects, fn e -> e.type == effect.type end)
    buff_type = (original_effect && original_effect.buff_type) || :absorb
    duration = (original_effect && original_effect.duration) || effect.duration || 10_000

    buff =
      BuffDebuff.new(%{
        id: spell.id,
        spell_id: spell.id,
        buff_type: buff_type,
        amount: effect.amount,
        duration: duration,
        is_debuff: is_debuff
      })

    case BuffManager.apply_buff(target_guid, buff, caster_guid) do
      {:ok, _timer_ref} ->
        Logger.debug(
          "Applied #{if is_debuff, do: "debuff", else: "buff"} #{spell.id} to #{target_guid}"
        )

        # Broadcast buff apply to the target
        CombatBroadcaster.send_buff_apply(target_guid, caster_guid, buff)
        :ok

      {:error, reason} ->
        Logger.warning("Failed to apply buff #{spell.id}: #{inspect(reason)}")
        :error
    end
  end

  defp apply_periodic_buff(caster_guid, target_guid, spell, effect, is_debuff) do
    # Get tick_interval from original spell effect
    original_effect = Enum.find(spell.effects, fn e -> e.type == effect.type end)
    tick_interval = (original_effect && original_effect.tick_interval) || 1000
    duration = (original_effect && original_effect.duration) || effect.duration || 10_000

    # For periodic effects, we use :periodic buff type
    buff =
      BuffDebuff.new(%{
        id: spell.id,
        spell_id: spell.id,
        buff_type: :periodic,
        amount: effect.amount,
        duration: duration,
        tick_interval: tick_interval,
        is_debuff: is_debuff
      })

    case BuffManager.apply_buff(target_guid, buff, caster_guid) do
      {:ok, _timer_ref} ->
        Logger.debug("Applied periodic effect #{spell.id} to #{target_guid}")
        # Broadcast buff apply to the target
        CombatBroadcaster.send_buff_apply(target_guid, caster_guid, buff)
        :ok

      {:error, reason} ->
        Logger.warning("Failed to apply periodic effect #{spell.id}: #{inspect(reason)}")
        :error
    end
  end

  defp apply_resurrect_effect(caster_guid, target_guid, spell, effect) do
    # Get health percent from effect amount (e.g., 35 for 35%)
    health_percent = effect.amount || 35.0

    case DeathManager.offer_resurrection(target_guid, caster_guid, spell.id, health_percent) do
      :ok ->
        # Get caster name for the offer packet (would normally come from session)
        # TODO: Look up from WorldManager session
        caster_name = "Player"

        # Send resurrection offer to target
        offer_packet =
          ServerResurrectOffer.new(
            caster_guid,
            caster_name,
            spell.id,
            health_percent,
            # 60 second timeout
            60_000
          )

        # Send to target player
        send_resurrect_offer_to_target(target_guid, offer_packet)

        Logger.info("Player #{caster_guid} offered resurrection to #{target_guid}")
        :ok

      {:error, :not_dead} ->
        Logger.debug("Resurrection failed: target #{target_guid} is not dead")
        :error
    end
  end

  defp send_resurrect_offer_to_target(target_guid, packet) do
    # Look up target's connection and send the packet
    alias BezgelorWorld.WorldManager

    case WorldManager.get_session_by_entity_guid(target_guid) do
      nil ->
        Logger.warning("Cannot send resurrect offer: no session for #{target_guid}")

      session ->
        writer = PacketWriter.new()
        {:ok, writer} = ServerResurrectOffer.write(packet, writer)
        payload = PacketWriter.to_binary(writer)

        send(session.connection_pid, {:send_packet, :server_resurrect_offer, payload})
    end
  end

  defp apply_damage_to_creature(world_key, creature_guid, attacker_guid, damage) do
    case WorldInstance.damage_creature(world_key, creature_guid, attacker_guid, damage) do
      {:ok, :killed, result} ->
        %{creature_guid: creature_guid, rewards: result}

      {:ok, :damaged, _result} ->
        nil

      {:error, reason} ->
        Logger.debug("Failed to damage creature #{creature_guid}: #{inspect(reason)}")
        nil
    end
  end

  # Check if GUID is a creature (type bits = 2 in bits 60-63)
  defp is_creature_guid?(guid) when is_integer(guid) and guid > 0 do
    type_bits = bsr(guid, 60) &&& 0xF
    type_bits == 2
  end

  defp is_creature_guid?(_), do: false

  defp handle_cast_start(spell, _packet, player_guid, _cast_time, state) do
    # Get caster info from session
    position = state.session_data[:position] || {0.0, 0.0, 0.0}
    yaw = state.session_data[:yaw] || 0.0
    caster_id = player_guid &&& 0xFFFFFFFF

    # Generate unique casting ID
    casting_id = :erlang.unique_integer([:positive, :monotonic]) &&& 0xFFFFFFFF

    # Build ServerSpellStart with proper format
    start_packet = ServerSpellStart.new(
      casting_id: casting_id,
      spell4_id: spell.id,
      caster_id: caster_id,
      primary_target_id: caster_id,
      position: position,
      yaw: yaw,
      user_initiated: true
    )

    send_packet(:server_spell_start, start_packet, state)
  end

  defp handle_cancel_cast(state) do
    player_guid = state.session_data[:entity_guid]

    case SpellManager.cancel_cast(player_guid) do
      :ok ->
        send_cast_result(:interrupted, :none, 0, state)

      {:error, :not_casting} ->
        {:ok, state}
    end
  end

  # Validation helpers

  defp validate_target(spell, packet, _state) do
    case spell.target_type do
      :self ->
        # Self-target doesn't need a target
        true

      :enemy ->
        # Requires enemy target
        packet.target_guid != 0

      :ally ->
        # Requires ally target
        packet.target_guid != 0

      :ground ->
        # Requires ground position
        true

      :aoe ->
        # AoE can be ground or target
        true
    end
  end

  defp validate_range(spell, packet, state) do
    if spell.range == 0.0 do
      # Self-cast, no range check
      true
    else
      entity = state.session_data[:entity]

      if entity == nil do
        true
      else
        # Simple distance check (would need target position lookup in real impl)
        # For Phase 8, just allow if we have a target
        packet.target_guid != 0 or spell.target_type == :self
      end
    end
  end

  # Packet sending helpers

  defp send_cast_result(result, reason, spell_id, state) do
    packet = %ServerCastResult{
      result: result,
      reason: reason,
      spell_id: spell_id
    }

    send_packet(:server_cast_result, packet, state)
  end

  defp send_spell_start_go_and_extra(spell_start, spell_go, extra_packets, state) do
    # Encode ServerSpellStart
    start_writer = PacketWriter.new()
    {:ok, start_writer} = ServerSpellStart.write(spell_start, start_writer)
    start_data = PacketWriter.to_binary(start_writer)

    # Encode ServerSpellGo
    go_writer = PacketWriter.new()
    {:ok, go_writer} = ServerSpellGo.write(spell_go, go_writer)
    go_data = PacketWriter.to_binary(go_writer)

    # Send extra packets (like teleport) BEFORE spell packets so movement happens first
    packets =
      extra_packets ++
      [
        {:server_spell_start, start_data},
        {:server_spell_go, go_data}
      ]

    {:reply_multi_world_encrypted, packets, state}
  end

  defp send_packet(opcode, packet, state) do
    writer = PacketWriter.new()

    {:ok, writer} =
      case opcode do
        :server_spell_start -> ServerSpellStart.write(packet, writer)
        :server_spell_go -> ServerSpellGo.write(packet, writer)
        :server_spell_finish -> ServerSpellFinish.write(packet, writer)
        :server_spell_effect -> ServerSpellEffect.write(packet, writer)
        :server_cast_result -> ServerCastResult.write(packet, writer)
        :server_cooldown -> ServerCooldown.write(packet, writer)
      end

    packet_data = PacketWriter.to_binary(writer)
    # Use world encrypted for all spell packets on the world server
    {:reply_world_encrypted, opcode, packet_data, state}
  end

  defp build_effect_packet(caster_guid, target_guid, spell_id, effect) do
    case effect.type do
      :damage ->
        ServerSpellEffect.damage(
          caster_guid,
          target_guid,
          spell_id,
          effect.amount,
          effect.is_crit
        )

      :heal ->
        ServerSpellEffect.heal(caster_guid, target_guid, spell_id, effect.amount, effect.is_crit)

      :buff ->
        ServerSpellEffect.buff(caster_guid, target_guid, spell_id, effect.amount)

      _ ->
        ServerSpellEffect.damage(
          caster_guid,
          target_guid,
          spell_id,
          effect.amount,
          effect.is_crit
        )
    end
  end

  # Get combat stats for the casting player
  defp get_caster_stats(state) do
    alias BezgelorCore.CharacterStats

    character = state.session_data[:character]
    entity_guid = state.session_data[:entity_guid]

    base_stats =
      if character do
        CharacterStats.compute_combat_stats(character)
      else
        # Fallback for tests without full session
        %{power: 100, tech: 100, support: 100, crit_chance: 10, armor: 0.0}
      end

    # Apply buff modifiers if entity has buffs
    if entity_guid do
      power_mod = BuffManager.get_stat_modifier(entity_guid, :power)
      tech_mod = BuffManager.get_stat_modifier(entity_guid, :tech)
      support_mod = BuffManager.get_stat_modifier(entity_guid, :support)
      crit_mod = BuffManager.get_stat_modifier(entity_guid, :crit_chance)

      CharacterStats.apply_buff_modifiers(base_stats, %{
        power: power_mod,
        tech: tech_mod,
        support: support_mod,
        crit_chance: crit_mod
      })
    else
      base_stats
    end
  end
end
