defmodule BezgelorWorld.GossipManager do
  @moduledoc """
  Manages NPC gossip/dialogue for ambient chat.

  ## Overview

  Handles proximity-based gossip triggering for ambient NPC chat. When a player
  comes within range of an NPC with a gossipSetId, the NPC can speak a random
  line from their gossip entries.

  ## Proximity Ranges

  The `gossipProximityEnum` field controls when gossip triggers:
  - 0: Click-only, no ambient gossip
  - 1: 15 units (close range)
  - 2: 30 units (medium range)

  ## Cooldowns

  Each gossip set has a cooldown (in seconds) to prevent spam. The caller
  is responsible for tracking when each NPC last triggered gossip.

  ## Usage

      # Check if proximity gossip should trigger
      if GossipManager.should_trigger_proximity?(gossip_set, npc_pos, player_pos, last_trigger) do
        entries = GossipManager.get_creature_gossip_entries(creature_id)
        if entry = GossipManager.select_gossip_entry(entries, players) do
          packet = GossipManager.build_gossip_packet(creature, entry)
          send(connection_pid, {:send_packet, :server_chat_npc, packet_data})
        end
      end
  """

  alias BezgelorData.Store
  alias BezgelorProtocol.Packets.World.ServerChatNpc

  require Logger

  # gossipProximityEnum -> range in game units
  @proximity_ranges %{
    0 => nil,
    1 => 15.0,
    2 => 30.0
  }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Select a random gossip entry from valid entries for nearby players.

  Filters entries by prerequisites (currently always passes) and returns
  a random valid entry. Returns nil if no valid entries exist.

  ## Parameters

  - `entries` - List of gossip entry maps with `:localizedTextId`, `:prerequisiteId`, etc.
  - `players` - List of player data maps (for future prerequisite checking)

  ## Returns

  A gossip entry map or nil if no valid entries.
  """
  @spec select_gossip_entry([map()], [map()]) :: map() | nil
  def select_gossip_entry([], _players), do: nil

  def select_gossip_entry(entries, players) do
    entries
    |> Enum.filter(&prerequisite_met?(&1, players))
    |> case do
      [] -> nil
      valid -> Enum.random(valid)
    end
  end

  @doc """
  Check if proximity gossip should trigger based on range and cooldown.

  ## Parameters

  - `gossip_set` - Map with `:gossipProximityEnum` and `:cooldown` fields
  - `npc_position` - `{x, y, z}` tuple of NPC position
  - `player_position` - `{x, y, z}` tuple of player position
  - `last_trigger` - Unix timestamp (seconds) of last trigger, or nil if never

  ## Returns

  `true` if gossip should trigger, `false` otherwise.
  """
  @spec should_trigger_proximity?(map(), tuple(), tuple(), integer() | nil) :: boolean()
  def should_trigger_proximity?(gossip_set, npc_position, player_position, last_trigger) do
    range = @proximity_ranges[gossip_set.gossipProximityEnum]

    cond do
      # Click-only NPCs don't do proximity gossip
      is_nil(range) ->
        false

      # Check cooldown
      on_cooldown?(last_trigger, gossip_set.cooldown) ->
        false

      # Check distance
      true ->
        distance(npc_position, player_position) <= range
    end
  end

  @doc """
  Build a ServerChatNpc packet for a gossip entry.

  ## Parameters

  - `creature` - Creature data map with `:localizedTextIdName`
  - `gossip_entry` - Gossip entry map with `:localizedTextId`

  ## Returns

  A `ServerChatNpc` struct ready to be serialized and sent.
  """
  @spec build_gossip_packet(map(), map()) :: ServerChatNpc.t()
  def build_gossip_packet(creature, gossip_entry) do
    %ServerChatNpc{
      channel_type: ServerChatNpc.npc_say(),
      chat_id: 0,
      unit_name_text_id: Map.get(creature, :localizedTextIdName, 0),
      message_text_id: gossip_entry.localizedTextId
    }
  end

  @doc """
  Get gossip entries for a creature's gossip set.

  Looks up the creature's gossipSetId and returns all entries for that set.

  ## Parameters

  - `creature_id` - The creature ID to look up

  ## Returns

  List of gossip entry maps, or empty list if none found.
  """
  @spec get_creature_gossip_entries(non_neg_integer()) :: [map()]
  def get_creature_gossip_entries(creature_id) do
    with {:ok, creature} <- Store.get_creature_full(creature_id),
         gossip_set_id when gossip_set_id > 0 <- Map.get(creature, :gossipSetId, 0) do
      Store.get_gossip_entries_for_set(gossip_set_id)
    else
      _ -> []
    end
  end

  @doc """
  Get the proximity range for a gossipProximityEnum value.

  ## Parameters

  - `proximity_enum` - The gossipProximityEnum value (0, 1, or 2)

  ## Returns

  Range in game units, or nil for click-only NPCs.
  """
  @spec get_proximity_range(non_neg_integer()) :: float() | nil
  def get_proximity_range(proximity_enum) do
    Map.get(@proximity_ranges, proximity_enum)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp prerequisite_met?(%{prerequisiteId: 0}, _players), do: true

  defp prerequisite_met?(%{prerequisiteId: _prereq_id}, _players) do
    # TODO: Wire to PrerequisiteChecker when needed
    # For now, show all entries
    true
  end

  defp on_cooldown?(nil, _cooldown), do: false
  defp on_cooldown?(_last_trigger, 0), do: false

  defp on_cooldown?(last_trigger, cooldown) do
    now = System.system_time(:second)
    now - last_trigger < cooldown
  end

  defp distance({x1, y1, z1}, {x2, y2, z2}) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    :math.sqrt(dx * dx + dy * dy + dz * dz)
  end
end
