defmodule BezgelorWorld.Quest.SessionQuestManager do
  @moduledoc """
  Session-based quest management for efficient in-memory quest tracking.

  ## Overview

  This module handles quest operations using session_data stored in the
  Connection process, avoiding database queries for every game event.

  ## Event Processing

  When a game event occurs (kill, loot, etc.), the Connection process
  receives a `{:game_event, type, data}` message and delegates to this module.
  We iterate through active_quests in session_data, check for matching
  objectives, and return updated session_data.

  ## Quest Lifecycle

  1. Accept: `accept_quest/3` - adds to session + DB
  2. Progress: `process_game_event/3` - updates session, marks dirty
  3. Complete: detected via `check_quest_completable/2`
  4. Turn-in: `turn_in_quest/3` - moves to completed, persists

  ## Usage

      # In Connection.handle_info
      def handle_info({:game_event, event_type, event_data}, state) do
        {session_data, packets} = SessionQuestManager.process_game_event(
          state.session_data,
          event_type,
          event_data
        )
        # Send packets and update state
      end
  """

  alias BezgelorWorld.Quest.QuestCache
  alias BezgelorDb.Quests
  alias BezgelorData.Store
  alias BezgelorProtocol.Packets.World.{ServerQuestUpdate, ServerQuestAdd, ServerQuestRemove}
  alias BezgelorProtocol.PacketWriter

  require Logger

  # ============================================================================
  # Objective Type Constants (all 40 types from quest_objectives data)
  # ============================================================================

  # Combat objectives
  @type_kill_creature 2        # 598 objectives - Kill specific creature
  @type_kill_creature_type 22  # 511 objectives - Kill creatures of type/tier
  @type_kill_elite 23          # 96 objectives - Kill elite creature

  # Item objectives
  @type_collect_item 3         # 350 objectives - Collect/loot item
  @type_loot_item 10           # 52 objectives - Loot item from creature
  @type_use_item 8             # 498 objectives - Use an item
  @type_deliver_item 6         # Deliver item to NPC
  @type_equip_item 7           # Equip specific item
  @type_craft_item 13          # 3 objectives - Craft item

  # Interaction objectives
  @type_talk_to_npc 4          # 327 objectives - Talk to NPC
  @type_interact_object 12     # 1187 objectives - Interact with object
  @type_activate_datacube 20   # 11 objectives - Activate datacube/lore
  @type_scan_creature 21       # 10 objectives - Scan creature

  # Location objectives
  @type_enter_location 5       # 1556 objectives - Enter location/zone
  @type_explore 25             # 152 objectives - Explore location
  @type_discover_poi 15        # 26 objectives - Discover point of interest

  # Escort/defense objectives
  @type_escort_npc 14          # 426 objectives - Escort/protect NPC
  @type_defend_location 18     # 35 objectives - Defend location
  @type_escort_to_location 24  # 39 objectives - Escort NPC to location

  # Ability objectives
  @type_use_ability 17         # 199 objectives - Use spell/ability

  # Resource objectives
  @type_gather_resource 33     # 215 objectives - Gather resource node

  # Event/sequence objectives
  @type_complete_event 31      # 260 objectives - Complete public event
  @type_achieve_condition 32   # 709 objectives - Achieve condition/state
  @type_objective_sequence 11  # 128 objectives - Complete objective sequence
  @type_complete_dungeon 9     # 18 objectives - Complete dungeon event
  @type_timed_event 16         # 55 objectives - Complete timed event

  # Path objectives
  @type_path_mission 19        # 2 objectives - Complete path mission

  # PvP/competitive objectives
  @type_win_pvp 28             # 5 objectives - Win PvP match/battleground
  @type_capture_point 29       # 2 objectives - Capture objective point
  @type_challenge 35           # 10 objectives - Complete challenge

  # Specialized objectives
  @type_reputation 36          # 6 objectives - Reach reputation level
  @type_level_requirement 37   # 4 objectives - Reach character level
  @type_housing 39             # 2 objectives - Housing interaction
  @type_mount 40               # 2 objectives - Mount related
  @type_costume 41             # 2 objectives - Costume/appearance
  @type_title 42               # 2 objectives - Earn title
  @type_achievement 44         # 7 objectives - Earn achievement
  @type_currency 46            # 1 objective - Earn/spend currency
  @type_social 47              # 2 objectives - Social interaction
  @type_guild 48               # 2 objectives - Guild related

  # Generic/script-triggered (most common - fallback for many types)
  @type_generic 38             # 2520 objectives - Script-triggered
  @type_special 27             # 1 objective - Special scripted

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Process a game event and update any matching quest objectives.

  Iterates through all active quests in session_data, checks each objective
  for a match, increments progress, and builds packets to send to the client.

  ## Returns

  `{updated_session_data, packets_to_send}` where packets is a list of
  `{opcode, binary}` tuples.
  """
  @spec process_game_event(map(), atom(), map()) :: {map(), [{atom(), binary()}]}
  def process_game_event(session_data, event_type, event_data) do
    active_quests = session_data[:active_quests] || %{}

    {updated_quests, packets} =
      Enum.reduce(active_quests, {%{}, []}, fn {quest_id, quest}, {quests_acc, packets_acc} ->
        {updated_quest, quest_packets} = process_quest_event(quest, event_type, event_data)
        {Map.put(quests_acc, quest_id, updated_quest), packets_acc ++ quest_packets}
      end)

    # Check if any quests became completable
    updated_quests = check_all_completable(updated_quests)

    updated_session = Map.put(session_data, :active_quests, updated_quests)

    # Mark session as dirty if we updated anything
    updated_session =
      if packets != [] do
        Map.put(updated_session, :quest_dirty, true)
      else
        updated_session
      end

    {updated_session, packets}
  end

  @doc """
  Accept a new quest for the character.

  Adds the quest to both session_data and the database.

  ## Returns

  `{:ok, updated_session_data, packet}` or `{:error, reason}`
  """
  @spec accept_quest(map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map(), {atom(), binary()}} | {:error, atom()}
  def accept_quest(session_data, character_id, quest_id) do
    active_quests = session_data[:active_quests] || %{}

    cond do
      Map.has_key?(active_quests, quest_id) ->
        {:error, :already_have_quest}

      map_size(active_quests) >= 25 ->
        {:error, :quest_log_full}

      true ->
        case QuestCache.create_session_quest(quest_id) do
          {:ok, session_quest} ->
            # Add to session
            updated_quests = Map.put(active_quests, quest_id, session_quest)
            updated_session = Map.put(session_data, :active_quests, updated_quests)

            # Persist to DB
            objectives =
              Enum.map(session_quest.objectives, fn obj ->
                %{type: obj.type, data: obj.data, target: obj.target}
              end)

            progress = Quests.init_progress(objectives)
            Quests.accept_quest(character_id, quest_id, progress: progress)

            # Build packet
            packet = build_quest_add_packet(session_quest)

            Logger.info("Character #{character_id} accepted quest #{quest_id}")
            {:ok, updated_session, packet}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Abandon a quest.

  Removes from both session_data and database.

  ## Returns

  `{:ok, updated_session_data, packet}` or `{:error, reason}`
  """
  @spec abandon_quest(map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map(), {atom(), binary()}} | {:error, atom()}
  def abandon_quest(session_data, character_id, quest_id) do
    active_quests = session_data[:active_quests] || %{}

    case Map.pop(active_quests, quest_id) do
      {nil, _} ->
        {:error, :quest_not_found}

      {_quest, remaining_quests} ->
        # Remove from session
        updated_session = Map.put(session_data, :active_quests, remaining_quests)

        # Remove from DB
        Quests.abandon_quest(character_id, quest_id)

        # Build packet
        packet = build_quest_remove_packet(quest_id)

        Logger.info("Character #{character_id} abandoned quest #{quest_id}")
        {:ok, updated_session, packet}
    end
  end

  @doc """
  Turn in a completed quest.

  Grants rewards, moves to completed_quest_ids, persists to DB history.

  ## Returns

  `{:ok, updated_session_data, packet}` or `{:error, reason}`
  """
  @spec turn_in_quest(map(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map(), {atom(), binary()}} | {:error, atom()}
  def turn_in_quest(session_data, character_id, quest_id) do
    active_quests = session_data[:active_quests] || %{}
    completed_ids = session_data[:completed_quest_ids] || MapSet.new()

    case Map.get(active_quests, quest_id) do
      nil ->
        {:error, :quest_not_found}

      %{state: state} when state != :complete ->
        {:error, :quest_not_complete}

      quest ->
        # Remove from active, add to completed
        remaining_quests = Map.delete(active_quests, quest_id)
        updated_completed = MapSet.put(completed_ids, quest_id)

        updated_session =
          session_data
          |> Map.put(:active_quests, remaining_quests)
          |> Map.put(:completed_quest_ids, updated_completed)

        # Persist to DB (this also moves to history)
        case Quests.turn_in_quest(character_id, quest_id) do
          {:ok, _history} ->
            packet = build_quest_remove_packet(quest_id)
            Logger.info("Character #{character_id} completed quest #{quest_id}")
            {:ok, updated_session, packet}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Check if a quest has all objectives complete.
  """
  @spec check_quest_completable(map()) :: boolean()
  def check_quest_completable(quest) do
    Enum.all?(quest.objectives, fn obj ->
      obj.current >= obj.target
    end)
  end

  @doc """
  Update a specific objective's progress in session.

  ## Returns

  Updated quest map with the objective incremented.
  """
  @spec update_objective(map(), non_neg_integer(), non_neg_integer()) :: map()
  def update_objective(quest, objective_index, increment \\ 1) do
    objectives =
      Enum.map(quest.objectives, fn obj ->
        if obj.index == objective_index do
          new_current = min(obj.current + increment, obj.target)
          %{obj | current: new_current}
        else
          obj
        end
      end)

    %{quest | objectives: objectives, dirty: true}
  end

  # ============================================================================
  # Private - Event Processing
  # ============================================================================

  defp process_quest_event(quest, event_type, event_data) do
    # Skip completed quests
    if quest.state == :complete do
      {quest, []}
    else
      {updated_quest, packets} =
        quest.objectives
        |> Enum.with_index()
        |> Enum.reduce({quest, []}, fn {obj, _idx}, {q, pkts} ->
          if obj.current < obj.target and matches_event?(event_type, obj.type, obj.data, event_data) do
            # Increment the objective
            updated_q = update_objective(q, obj.index)
            new_current = get_objective_current(updated_q, obj.index)

            # Build update packet
            packet = build_quest_update_packet(q.quest_id, q.state, obj.index, new_current)

            {updated_q, pkts ++ [packet]}
          else
            {q, pkts}
          end
        end)

      {updated_quest, packets}
    end
  end

  defp get_objective_current(quest, index) do
    case Enum.find(quest.objectives, &(&1.index == index)) do
      nil -> 0
      obj -> obj.current
    end
  end

  defp check_all_completable(quests) do
    Map.new(quests, fn {quest_id, quest} ->
      if quest.state == :accepted and check_quest_completable(quest) do
        {quest_id, %{quest | state: :complete}}
      else
        {quest_id, quest}
      end
    end)
  end

  # ============================================================================
  # Private - Event Matching (from ObjectiveHandler)
  # ============================================================================

  defp matches_event?(:kill, obj_type, obj_data, %{creature_id: creature_id}) do
    case obj_type do
      @type_kill_creature -> obj_data == creature_id
      @type_kill_creature_type -> matches_creature_type?(creature_id, obj_data)
      @type_kill_elite -> is_elite_creature?(creature_id) and (obj_data == 0 or obj_data == creature_id)
      @type_generic -> obj_data == creature_id
      _ -> false
    end
  end

  defp matches_event?(:loot, obj_type, obj_data, %{item_id: item_id}) do
    case obj_type do
      @type_collect_item -> obj_data == item_id
      @type_loot_item -> obj_data == item_id
      @type_generic -> obj_data == item_id
      _ -> false
    end
  end

  defp matches_event?(:interact, obj_type, obj_data, %{object_id: object_id}) do
    case obj_type do
      @type_interact_object -> obj_data == object_id
      @type_generic -> obj_data == object_id
      _ -> false
    end
  end

  defp matches_event?(:enter_location, obj_type, obj_data, %{location_id: location_id}) do
    case obj_type do
      @type_enter_location -> obj_data == location_id
      @type_explore -> obj_data == location_id
      @type_generic -> obj_data == location_id
      _ -> false
    end
  end

  defp matches_event?(:talk_npc, obj_type, obj_data, %{creature_id: creature_id}) do
    case obj_type do
      @type_talk_to_npc -> obj_data == creature_id
      @type_generic -> obj_data == creature_id
      _ -> false
    end
  end

  defp matches_event?(:use_item, obj_type, obj_data, %{item_id: item_id}) do
    case obj_type do
      @type_use_item -> obj_data == item_id
      @type_generic -> obj_data == item_id
      _ -> false
    end
  end

  defp matches_event?(:use_ability, obj_type, obj_data, %{spell_id: spell_id}) do
    case obj_type do
      @type_use_ability -> obj_data == spell_id
      @type_generic -> obj_data == spell_id
      _ -> false
    end
  end

  defp matches_event?(:gather, obj_type, obj_data, %{node_id: node_id}) do
    case obj_type do
      @type_gather_resource -> obj_data == node_id
      @type_generic -> obj_data == node_id
      _ -> false
    end
  end

  defp matches_event?(:complete_event, obj_type, obj_data, %{event_id: event_id}) do
    case obj_type do
      @type_complete_event -> obj_data == event_id
      @type_generic -> obj_data == event_id
      _ -> false
    end
  end

  defp matches_event?(:condition_met, obj_type, obj_data, %{condition_id: condition_id}) do
    case obj_type do
      @type_achieve_condition -> obj_data == condition_id
      @type_generic -> obj_data == condition_id
      _ -> false
    end
  end

  # Item delivery to NPC
  defp matches_event?(:deliver_item, obj_type, obj_data, %{item_id: item_id, npc_id: npc_id}) do
    case obj_type do
      @type_deliver_item -> obj_data == item_id or obj_data == npc_id
      @type_generic -> obj_data == item_id
      _ -> false
    end
  end

  # Equipment changes
  defp matches_event?(:equip_item, obj_type, obj_data, %{item_id: item_id}) do
    case obj_type do
      @type_equip_item -> obj_data == item_id
      @type_generic -> obj_data == item_id
      _ -> false
    end
  end

  # Crafting
  defp matches_event?(:craft, obj_type, obj_data, %{item_id: item_id}) do
    case obj_type do
      @type_craft_item -> obj_data == item_id
      @type_generic -> obj_data == item_id
      _ -> false
    end
  end

  # Datacube/lore activation
  defp matches_event?(:datacube, obj_type, obj_data, %{datacube_id: datacube_id}) do
    case obj_type do
      @type_activate_datacube -> obj_data == datacube_id
      @type_generic -> obj_data == datacube_id
      _ -> false
    end
  end

  # Creature scanning
  defp matches_event?(:scan, obj_type, obj_data, %{creature_id: creature_id}) do
    case obj_type do
      @type_scan_creature -> obj_data == creature_id
      @type_generic -> obj_data == creature_id
      _ -> false
    end
  end

  # Point of interest discovery
  defp matches_event?(:discover_poi, obj_type, obj_data, %{poi_id: poi_id}) do
    case obj_type do
      @type_discover_poi -> obj_data == poi_id
      @type_generic -> obj_data == poi_id
      _ -> false
    end
  end

  # Escort NPC completion
  defp matches_event?(:escort_complete, obj_type, obj_data, %{escort_id: escort_id}) do
    case obj_type do
      @type_escort_npc -> obj_data == escort_id
      @type_escort_to_location -> obj_data == escort_id
      @type_generic -> obj_data == escort_id
      _ -> false
    end
  end

  # Defense objective completion
  defp matches_event?(:defend_complete, obj_type, obj_data, %{location_id: location_id}) do
    case obj_type do
      @type_defend_location -> obj_data == location_id
      @type_generic -> obj_data == location_id
      _ -> false
    end
  end

  # Dungeon event completion
  defp matches_event?(:dungeon_complete, obj_type, obj_data, %{dungeon_id: dungeon_id}) do
    case obj_type do
      @type_complete_dungeon -> obj_data == dungeon_id
      @type_generic -> obj_data == dungeon_id
      _ -> false
    end
  end

  # Objective sequence step
  defp matches_event?(:sequence_step, obj_type, obj_data, %{sequence_id: sequence_id}) do
    case obj_type do
      @type_objective_sequence -> obj_data == sequence_id
      @type_generic -> obj_data == sequence_id
      _ -> false
    end
  end

  # Timed event completion
  defp matches_event?(:timed_complete, obj_type, obj_data, %{timer_id: timer_id}) do
    case obj_type do
      @type_timed_event -> obj_data == timer_id
      @type_generic -> obj_data == timer_id
      _ -> false
    end
  end

  # Path mission completion
  defp matches_event?(:path_complete, obj_type, obj_data, %{mission_id: mission_id}) do
    case obj_type do
      @type_path_mission -> obj_data == mission_id
      @type_generic -> obj_data == mission_id
      _ -> false
    end
  end

  # PvP victory
  defp matches_event?(:pvp_win, obj_type, obj_data, %{battleground_id: battleground_id}) do
    case obj_type do
      @type_win_pvp -> obj_data == 0 or obj_data == battleground_id
      @type_generic -> obj_data == battleground_id
      _ -> false
    end
  end

  # Capture point
  defp matches_event?(:capture, obj_type, obj_data, %{point_id: point_id}) do
    case obj_type do
      @type_capture_point -> obj_data == point_id
      @type_generic -> obj_data == point_id
      _ -> false
    end
  end

  # Challenge completion
  defp matches_event?(:challenge_complete, obj_type, obj_data, %{challenge_id: challenge_id}) do
    case obj_type do
      @type_challenge -> obj_data == challenge_id
      @type_generic -> obj_data == challenge_id
      _ -> false
    end
  end

  # Reputation gain
  defp matches_event?(:reputation_gain, obj_type, obj_data, %{faction_id: faction_id, level: level}) do
    case obj_type do
      @type_reputation -> obj_data == faction_id and level >= get_required_rep_level(obj_data)
      @type_generic -> obj_data == faction_id
      _ -> false
    end
  end

  # Level up
  defp matches_event?(:level_up, obj_type, obj_data, %{level: level}) do
    case obj_type do
      @type_level_requirement -> level >= obj_data
      @type_generic -> level >= obj_data
      _ -> false
    end
  end

  # Housing interaction
  defp matches_event?(:housing, obj_type, obj_data, %{housing_id: housing_id}) do
    case obj_type do
      @type_housing -> obj_data == housing_id or obj_data == 0
      @type_generic -> obj_data == housing_id
      _ -> false
    end
  end

  # Mount usage
  defp matches_event?(:mount, obj_type, obj_data, %{mount_id: mount_id}) do
    case obj_type do
      @type_mount -> obj_data == mount_id or obj_data == 0
      @type_generic -> obj_data == mount_id
      _ -> false
    end
  end

  # Costume/appearance change
  defp matches_event?(:costume, obj_type, obj_data, %{costume_id: costume_id}) do
    case obj_type do
      @type_costume -> obj_data == costume_id or obj_data == 0
      @type_generic -> obj_data == costume_id
      _ -> false
    end
  end

  # Title earned
  defp matches_event?(:title, obj_type, obj_data, %{title_id: title_id}) do
    case obj_type do
      @type_title -> obj_data == title_id
      @type_generic -> obj_data == title_id
      _ -> false
    end
  end

  # Achievement earned
  defp matches_event?(:achievement, obj_type, obj_data, %{achievement_id: achievement_id}) do
    case obj_type do
      @type_achievement -> obj_data == achievement_id
      @type_generic -> obj_data == achievement_id
      _ -> false
    end
  end

  # Currency transaction
  defp matches_event?(:currency, obj_type, obj_data, %{currency_id: currency_id, amount: amount}) do
    case obj_type do
      @type_currency -> obj_data == currency_id and amount > 0
      @type_generic -> obj_data == currency_id
      _ -> false
    end
  end

  # Social interaction (emotes, /say to NPC, etc.)
  defp matches_event?(:social, obj_type, obj_data, %{social_type: social_type}) do
    case obj_type do
      @type_social -> obj_data == social_type or obj_data == 0
      @type_generic -> obj_data == social_type
      _ -> false
    end
  end

  # Guild activity
  defp matches_event?(:guild, obj_type, obj_data, %{guild_action: guild_action}) do
    case obj_type do
      @type_guild -> obj_data == guild_action or obj_data == 0
      @type_generic -> obj_data == guild_action
      _ -> false
    end
  end

  # Special scripted events
  defp matches_event?(:special, obj_type, obj_data, %{special_id: special_id}) do
    case obj_type do
      @type_special -> obj_data == special_id
      @type_generic -> obj_data == special_id
      _ -> false
    end
  end

  defp matches_event?(_, _, _, _), do: false

  # Helper for reputation level checks
  defp get_required_rep_level(_faction_data) do
    # Default to level 0, can be extended to look up actual requirements
    0
  end

  defp matches_creature_type?(creature_id, type_data) do
    case Store.get_creature_full(creature_id) do
      {:ok, creature} ->
        tier_id = Map.get(creature, :tierId) || Map.get(creature, :tier_id)
        archetype_id = Map.get(creature, :archetypeId) || Map.get(creature, :archetype_id)
        tier_id == type_data or archetype_id == type_data

      :error ->
        false
    end
  end

  defp is_elite_creature?(creature_id) do
    case Store.get_creature_full(creature_id) do
      {:ok, creature} ->
        difficulty_id = Map.get(creature, :difficultyId) || Map.get(creature, :difficulty_id) || 0
        difficulty_id >= 3

      :error ->
        false
    end
  end

  # ============================================================================
  # Private - Packet Building
  # ============================================================================

  defp build_quest_update_packet(quest_id, state, objective_index, current) do
    packet = %ServerQuestUpdate{
      quest_id: quest_id,
      state: state,
      objective_index: objective_index,
      current: current
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerQuestUpdate.write(packet, writer)
    {:server_quest_update, PacketWriter.to_binary(writer)}
  end

  defp build_quest_add_packet(session_quest) do
    # Convert objectives to format expected by ServerQuestAdd
    objectives =
      Enum.map(session_quest.objectives, fn obj ->
        %{target: obj.target}
      end)

    packet = %ServerQuestAdd{
      quest_id: session_quest.quest_id,
      objectives: objectives
    }

    writer = PacketWriter.new()
    {:ok, writer} = ServerQuestAdd.write(packet, writer)
    {:server_quest_add, PacketWriter.to_binary(writer)}
  end

  defp build_quest_remove_packet(quest_id) do
    packet = %ServerQuestRemove{quest_id: quest_id}
    writer = PacketWriter.new()
    {:ok, writer} = ServerQuestRemove.write(packet, writer)
    {:server_quest_remove, PacketWriter.to_binary(writer)}
  end
end
