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
    ServerSpellStart,
    ServerSpellFinish,
    ServerSpellEffect,
    ServerCastResult,
    ServerCooldown
  }

  alias BezgelorProtocol.{PacketReader, PacketWriter}
  alias BezgelorCore.{Spell, BuffDebuff}
  alias BezgelorWorld.{BuffManager, CombatBroadcaster, CreatureManager, SpellManager}

  import Bitwise

  require Logger

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    # Try to parse as cast spell first, then cancel
    case ClientCastSpell.read(reader) do
      {:ok, packet, _reader} ->
        handle_cast_spell(packet, state)

      {:error, _} ->
        # Try cancel cast (always succeeds since it's empty)
        {:ok, _packet, _reader} = ClientCancelCast.read(reader)
        handle_cancel_cast(state)
    end
  end

  defp handle_cast_spell(packet, state) do
    unless state.session_data[:in_world] do
      Logger.warning("Spell cast received before player entered world")
      {:error, :not_in_world}
    else
      process_cast(packet, state)
    end
  end

  defp process_cast(packet, state) do
    player_guid = state.session_data[:entity_guid]
    spell = Spell.get(packet.spell_id)

    cond do
      spell == nil ->
        send_cast_result(:failed, :not_known, packet.spell_id, state)

      not validate_target(spell, packet, state) ->
        send_cast_result(:failed, :invalid_target, packet.spell_id, state)

      not validate_range(spell, packet, state) ->
        send_cast_result(:failed, :out_of_range, packet.spell_id, state)

      true ->
        do_cast(spell, packet, player_guid, state)
    end
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

  defp handle_instant_cast(spell, packet, player_guid, result, state) do
    actual_target = if packet.target_guid == 0, do: player_guid, else: packet.target_guid

    # Broadcast telegraphs for this spell (if any)
    # Telegraphs show visual indicators where spell effects will land
    broadcast_spell_telegraphs(spell.id, player_guid, packet, state)

    # Send spell finish
    finish_packet = ServerSpellFinish.new(player_guid, spell.id)

    # Apply effects to targets and collect kill info
    {effect_packets, kill_info} =
      apply_spell_effects(player_guid, actual_target, spell, result.effects)

    # Send cooldown if applicable
    cooldown_packet =
      if spell.cooldown > 0 do
        ServerCooldown.new(spell.id, spell.cooldown)
      else
        nil
      end

    Logger.info("Instant cast: player #{player_guid} spell #{spell.name} on #{actual_target}")

    # Broadcast kill rewards if creature was killed
    if kill_info do
      # For now, broadcast only to the killer (future: nearby players)
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

      # Notify quest system of the kill - all combat participants receive credit
      zone_id = state.session_data[:zone_id] || 1
      instance_id = state.session_data[:zone_instance_id] || 1

      # Use participant_character_ids from death result for group kill credit
      participant_ids = kill_info.rewards[:participant_character_ids] || []

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

    send_spell_packets(finish_packet, effect_packets, cooldown_packet, state)
  end

  # Apply spell effects to targets, calling CreatureManager for damage to creatures
  # and BuffManager for buff/debuff effects
  defp apply_spell_effects(caster_guid, target_guid, spell, effects) do
    Enum.reduce(effects, {[], nil}, fn effect, {packets, kill_info} ->
      target = if spell.target_type == :self, do: caster_guid, else: target_guid
      packet = build_effect_packet(caster_guid, target, spell.id, effect)

      # Apply damage effects to creatures
      new_kill_info =
        if effect.type == :damage and is_creature_guid?(target) do
          apply_damage_to_creature(target, caster_guid, effect.amount)
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

      _ ->
        :ok
    end
  end

  defp apply_buff(caster_guid, target_guid, spell, effect, is_debuff) do
    # Get buff_type and duration from original spell effect (result effect doesn't have these)
    original_effect = Enum.find(spell.effects, fn e -> e.type == effect.type end)
    buff_type = (original_effect && original_effect.buff_type) || :absorb
    duration = (original_effect && original_effect.duration) || effect.duration || 10_000

    buff = BuffDebuff.new(%{
      id: spell.id,
      spell_id: spell.id,
      buff_type: buff_type,
      amount: effect.amount,
      duration: duration,
      is_debuff: is_debuff
    })

    case BuffManager.apply_buff(target_guid, buff, caster_guid) do
      {:ok, _timer_ref} ->
        Logger.debug("Applied #{if is_debuff, do: "debuff", else: "buff"} #{spell.id} to #{target_guid}")
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
    buff = BuffDebuff.new(%{
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

  defp apply_damage_to_creature(creature_guid, attacker_guid, damage) do
    case CreatureManager.damage_creature(creature_guid, attacker_guid, damage) do
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

  defp handle_cast_start(spell, packet, player_guid, cast_time, state) do
    target_guid = if packet.target_guid == 0, do: player_guid, else: packet.target_guid

    # Send cast start
    start_packet = ServerSpellStart.new(player_guid, spell.id, cast_time, target_guid)

    Logger.info("Cast start: player #{player_guid} spell #{spell.name} (#{cast_time}ms)")

    send_packet(:server_spell_start, start_packet, state)
  end

  defp handle_cancel_cast(state) do
    player_guid = state.session_data[:entity_guid]

    case SpellManager.cancel_cast(player_guid) do
      :ok ->
        # Get the spell that was being cast for the result packet
        # For simplicity, send a generic interrupted result
        Logger.info("Cast cancelled: player #{player_guid}")
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

  defp send_spell_packets(finish_packet, _effect_packets, _cooldown_packet, state) do
    # This is a simplified version - in a full implementation,
    # we'd send multiple packets
    # For now, just send the finish packet
    writer = PacketWriter.new()
    {:ok, writer} = ServerSpellFinish.write(finish_packet, writer)
    packet_data = PacketWriter.to_binary(writer)

    {:reply, :server_spell_finish, packet_data, state}
  end

  defp send_packet(opcode, packet, state) do
    writer = PacketWriter.new()

    {:ok, writer} =
      case opcode do
        :server_spell_start -> ServerSpellStart.write(packet, writer)
        :server_spell_finish -> ServerSpellFinish.write(packet, writer)
        :server_spell_effect -> ServerSpellEffect.write(packet, writer)
        :server_cast_result -> ServerCastResult.write(packet, writer)
        :server_cooldown -> ServerCooldown.write(packet, writer)
      end

    packet_data = PacketWriter.to_binary(writer)
    {:reply, opcode, packet_data, state}
  end

  defp build_effect_packet(caster_guid, target_guid, spell_id, effect) do
    case effect.type do
      :damage ->
        ServerSpellEffect.damage(caster_guid, target_guid, spell_id, effect.amount, effect.is_crit)

      :heal ->
        ServerSpellEffect.heal(caster_guid, target_guid, spell_id, effect.amount, effect.is_crit)

      :buff ->
        ServerSpellEffect.buff(caster_guid, target_guid, spell_id, effect.amount)

      _ ->
        ServerSpellEffect.damage(caster_guid, target_guid, spell_id, effect.amount, effect.is_crit)
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

  # Broadcast telegraphs for a spell (visual damage area indicators)
  defp broadcast_spell_telegraphs(spell_id, caster_guid, packet, state) do
    # Get caster position from session data or use target position as fallback
    caster_position = state.session_data[:position] || packet.target_position || {0.0, 0.0, 0.0}

    # Get caster rotation (default to 0 if not available)
    caster_rotation = state.session_data[:rotation] || 0.0

    # For now, just broadcast to the caster (future: nearby players in zone)
    # This ensures the caster sees their own telegraphs
    recipient_guids = [caster_guid]

    # Call CombatBroadcaster to look up and broadcast any telegraphs for this spell
    CombatBroadcaster.broadcast_spell_telegraphs(
      spell_id,
      caster_guid,
      caster_position,
      caster_rotation,
      recipient_guids
    )
  end
end
