defmodule BezgelorWorld.Handler.NpcHandler do
  @moduledoc """
  Handles NPC interaction events.

  When a player interacts with an NPC, determines the appropriate response:
  - Quest giver: offers available quests
  - Quest receiver: allows quest turn-in
  - Vendor: opens shop interface
  - Gossip NPC: shows dialogue options
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorData.Store
  alias BezgelorDb.{Characters, Quests}
  alias BezgelorProtocol.PacketReader
  alias BezgelorProtocol.Packets.World.{
    ClientNpcInteract,
    ServerQuestOffer
  }
  alias BezgelorWorld.{CombatBroadcaster, Quest.PrerequisiteChecker}

  require Logger

  # ============================================================================
  # Handler Behaviour
  # ============================================================================

  @impl true
  def handle(payload, state) do
    reader = PacketReader.new(payload)

    case ClientNpcInteract.read(reader) do
      {:ok, packet, _reader} ->
        character_id = state.session_data[:character_id]
        connection_pid = self()

        handle_interact(connection_pid, character_id, packet, state.session_data)
        {:ok, state}

      {:error, reason} ->
        Logger.warning("Failed to parse ClientNpcInteract: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Handle NPC interaction packet.

  Determines NPC type and responds appropriately.
  """
  @spec handle_interact(pid(), integer(), ClientNpcInteract.t(), map()) :: :ok
  def handle_interact(connection_pid, character_id, %ClientNpcInteract{} = packet, session_data) do
    npc_guid = packet.npc_guid

    # Extract creature ID from GUID (implementation-specific)
    creature_id = extract_creature_id(npc_guid, session_data)

    cond do
      is_nil(creature_id) ->
        Logger.warning("Could not extract creature ID from GUID #{npc_guid}")
        :ok

      Store.creature_quest_giver?(creature_id) ->
        # Notify quest system of NPC talk (for talk_to_npc objectives)
        CombatBroadcaster.notify_npc_talk(character_id, creature_id)
        handle_quest_giver(connection_pid, character_id, creature_id, npc_guid)

      Store.get_vendor_by_creature(creature_id) != :error ->
        CombatBroadcaster.notify_npc_talk(character_id, creature_id)
        handle_vendor(connection_pid, character_id, creature_id, npc_guid)

      true ->
        CombatBroadcaster.notify_npc_talk(character_id, creature_id)
        handle_generic_npc(connection_pid, character_id, creature_id, npc_guid)
    end
  end

  @doc """
  Handle interaction with a quest giver NPC.

  Looks up available quests and sends quest offer packet.
  """
  @spec handle_quest_giver(pid(), integer(), integer(), non_neg_integer()) :: :ok
  def handle_quest_giver(connection_pid, character_id, creature_id, npc_guid) do
    # Get quest IDs this creature can give
    quest_ids = Store.get_quests_for_creature_giver(creature_id)

    # Filter to quests the character can accept
    available_quests =
      quest_ids
      |> Enum.map(&get_quest_if_available(&1, character_id))
      |> Enum.reject(&is_nil/1)

    if length(available_quests) > 0 do
      packet = %ServerQuestOffer{
        npc_guid: npc_guid,
        quests: available_quests
      }

      send(connection_pid, {:send_packet, packet})
      Logger.debug("Offered #{length(available_quests)} quests from creature #{creature_id}")
    else
      # Check if there are turn-in quests
      if Store.creature_quest_receiver?(creature_id) do
        handle_quest_receiver(connection_pid, character_id, creature_id, npc_guid)
      else
        Logger.debug("No available quests from creature #{creature_id}")
        # Could send a gossip packet or empty response
      end
    end

    :ok
  end

  @doc """
  Handle interaction with a quest receiver NPC.

  Checks if player has any quests ready to turn in.
  """
  @spec handle_quest_receiver(pid(), integer(), integer(), non_neg_integer()) :: :ok
  def handle_quest_receiver(_connection_pid, character_id, creature_id, _npc_guid) do
    # Get quest IDs this creature can receive
    receivable_quest_ids = Store.get_quests_for_creature_receiver(creature_id)

    # Get player's completed quests that can be turned in here
    active_quests = Quests.get_active_quests(character_id)

    turnable_quests =
      active_quests
      |> Enum.filter(fn quest ->
        quest.state == :complete and quest.quest_id in receivable_quest_ids
      end)

    if length(turnable_quests) > 0 do
      # For now, just log - would send a turn-in dialog packet
      Logger.debug(
        "Character #{character_id} can turn in #{length(turnable_quests)} quests to creature #{creature_id}"
      )

      # TODO: Send ServerQuestTurnInOffer packet
    else
      Logger.debug("No quests to turn in at creature #{creature_id}")
    end

    :ok
  end

  @doc """
  Handle interaction with a vendor NPC.
  """
  @spec handle_vendor(pid(), integer(), integer(), non_neg_integer()) :: :ok
  def handle_vendor(_connection_pid, _character_id, creature_id, _npc_guid) do
    # Get vendor inventory
    items = Store.get_vendor_items_for_creature(creature_id)

    if length(items) > 0 do
      Logger.debug("Opening vendor #{creature_id} with #{length(items)} items")
      # TODO: Send ServerVendorOpen packet with items
    else
      Logger.warning("Vendor #{creature_id} has no items")
    end

    :ok
  end

  @doc """
  Handle interaction with a generic NPC (gossip, trainer, etc.).
  """
  @spec handle_generic_npc(pid(), integer(), integer(), non_neg_integer()) :: :ok
  def handle_generic_npc(_connection_pid, _character_id, creature_id, _npc_guid) do
    # Check for gossip
    case Store.get_creature_full(creature_id) do
      {:ok, creature} ->
        gossip_set_id = Map.get(creature, :gossipSetId)

        if gossip_set_id && gossip_set_id > 0 do
          Logger.debug("NPC #{creature_id} has gossip set #{gossip_set_id}")
          # TODO: Send gossip packet
        else
          Logger.debug("NPC #{creature_id} has no special interactions")
        end

      :error ->
        Logger.warning("Could not find creature data for #{creature_id}")
    end

    :ok
  end

  # Get quest data if the character can accept it
  defp get_quest_if_available(quest_id, character_id) do
    case Store.get_quest(quest_id) do
      {:ok, quest} ->
        # Get character data for prerequisite checks
        character = get_character_data(character_id)

        if character do
          case PrerequisiteChecker.can_accept_quest?(character, quest) do
            {:ok, true} ->
              build_quest_offer(quest)

            {:error, reason} ->
              Logger.debug("Character #{character_id} cannot accept quest #{quest_id}: #{reason}")
              nil
          end
        else
          Logger.warning("Character #{character_id} not found")
          nil
        end

      :error ->
        Logger.warning("Quest #{quest_id} not found in data store")
        nil
    end
  end

  # Get character data for prerequisite checks
  defp get_character_data(character_id) do
    case Characters.get_character(character_id) do
      nil ->
        nil

      character ->
        %{
          id: character.id,
          level: character.level,
          race_id: character.race_id,
          class_id: character.class_id,
          faction_id: character.faction_id
        }
    end
  end

  # Build quest offer entry for packet
  defp build_quest_offer(quest) do
    %{
      id: quest.id,
      title_text_id: Map.get(quest, :localizedTextIdName, 0),
      level: Map.get(quest, :suggestedMinLevel, 1),
      type: Map.get(quest, :type, 0),
      flags: Map.get(quest, :flags, 0)
    }
  end

  # Extract creature ID from entity GUID
  # This depends on how GUIDs are structured in the zone instance
  defp extract_creature_id(guid, session_data) do
    # The zone instance should maintain a mapping of GUID -> creature_id
    zone_instance = session_data[:zone_instance]

    if zone_instance do
      # Try to get from zone's entity registry
      case BezgelorWorld.Zone.Instance.get_entity_creature_id(zone_instance, guid) do
        {:ok, creature_id} -> creature_id
        :error -> nil
      end
    else
      # Fallback: try to decode from GUID format
      # WildStar GUIDs often encode entity type and ID
      decode_creature_id_from_guid(guid)
    end
  end

  # Attempt to decode creature ID from GUID structure
  defp decode_creature_id_from_guid(guid) when is_integer(guid) do
    # GUID format: upper bits = type, lower bits = ID
    # This is a simplified example - real format depends on WildStar protocol
    creature_id = Bitwise.band(guid, 0xFFFFFFFF)

    if creature_id > 0 and creature_id < 100_000 do
      creature_id
    else
      nil
    end
  end

  defp decode_creature_id_from_guid(_), do: nil
end
