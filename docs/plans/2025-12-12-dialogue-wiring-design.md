# Dialogue Wiring Design

**Date:** 2025-12-12
**Status:** Design Complete

## Overview

Wire the extracted gossip data (10,799 entries, 1,978 sets) to NPC interactions, enabling:
1. **Click-dialogue** - Open dialogue UI when clicking NPCs
2. **Ambient gossip** - NPCs speak random lines when players approach

## Key Discovery

The WildStar client handles dialogue display locally. The server only needs to:
- Send `ServerDialogStart` with NPC GUID for click-dialogue
- Send `ServerChatNPC` with text IDs for ambient barks

The client looks up `gossipSetId` from its local creature data and displays the appropriate text.

## Architecture

```
Click-Dialogue Flow:
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  ClientEntity   │────▶│  NpcHandler      │────▶│  ServerDialog   │
│  Interact (37)  │     │                  │     │  Start          │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                         │
                                                         ▼
                                                 Client shows UI
                                                 (local gossip data)

Ambient Gossip Flow:
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Zone tick      │────▶│  GossipManager   │────▶│  ServerChatNPC  │
│  Proximity      │     │                  │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

## Packet Definitions

### ServerDialogStart (0x0357)

Opens the dialogue UI for an NPC.

```elixir
%ServerDialogStart{
  dialog_unit_id: uint32,  # NPC entity GUID
  unused: bool             # always false
}
```

Binary format:
- 4 bytes: dialog_unit_id (little-endian)
- 1 byte: unused flag (0x00)

### ServerChatNPC (0x01C6)

Sends NPC chat using localized text IDs.

```elixir
%ServerChatNPC{
  channel: %Channel{
    type: uint14,    # ChatChannelType.NPCSay = 24
    chat_id: uint64  # always 0
  },
  unit_name_text_id: uint21,   # creature's localizedTextIdName
  message_text_id: uint21      # gossip entry's localizedTextId
}
```

### ClientEntityInteract (0x07EA)

Already partially implemented as `ClientNpcInteract`. Event types:
- 37 = Dialogue/Quest NPC
- 49 = Vendor
- 48 = Taxi
- 43 = Tradeskill Trainer
- (many more in NexusForever)

## Click-Dialogue Implementation

### Handler Changes

Update `NpcHandler` to check interaction event type:

```elixir
def handle_interact(connection_pid, character_id, packet, session_data) do
  npc_guid = packet.npc_guid
  creature_id = extract_creature_id(npc_guid, session_data)

  # Notify quest system regardless of event type
  CombatBroadcaster.notify_npc_talk(character_id, creature_id)

  case packet.event do
    37 ->  # Dialogue - just open the UI
      send_dialog_start(connection_pid, npc_guid)

    49 ->  # Vendor
      handle_vendor(connection_pid, character_id, creature_id, npc_guid)

    _ ->
      # Fallback to current behavior for other events
      handle_by_npc_type(connection_pid, character_id, creature_id, npc_guid)
  end
end

defp send_dialog_start(connection_pid, npc_guid) do
  packet = %ServerDialogStart{dialog_unit_id: npc_guid, unused: false}
  send(connection_pid, {:send_packet, packet})
end
```

### Why This Works

The client has all creature data locally, including `gossipSetId`. When it receives `ServerDialogStart`:
1. Looks up creature by GUID
2. Gets `gossipSetId` from creature data
3. Fetches gossip entries for that set
4. Displays dialogue UI with localized text
5. Shows action buttons (Quest, Vendor, etc.) based on creature flags

## Ambient Gossip Implementation

### GossipManager Module

New module to handle proximity-based NPC chatter:

```elixir
defmodule BezgelorWorld.GossipManager do
  alias BezgelorData.Store
  alias BezgelorWorld.Quest.PrerequisiteChecker

  # gossipProximityEnum values
  @proximity_ranges %{
    0 => nil,    # Click-only, no ambient
    1 => 15.0,   # Close range
    2 => 30.0    # Medium range
  }

  @doc """
  Check if NPC should broadcast ambient gossip to nearby players.
  Called periodically from zone tick.
  """
  def check_proximity_gossip(npc, nearby_players, npc_state) do
    with {:ok, creature} <- Store.get_creature_full(npc.creature_id),
         gossip_set_id when gossip_set_id > 0 <- Map.get(creature, :gossipSetId),
         {:ok, gossip_set} <- Store.get_gossip_set(gossip_set_id),
         range when range != nil <- @proximity_ranges[gossip_set.gossipProximityEnum],
         players_in_range <- filter_by_range(nearby_players, npc.position, range),
         true <- length(players_in_range) > 0,
         false <- on_cooldown?(npc_state, gossip_set_id),
         entries <- get_valid_entries(gossip_set_id, players_in_range),
         entry when entry != nil <- select_random_entry(entries) do

      broadcast_gossip(npc, creature, entry, players_in_range)
      {:cooldown, gossip_set.cooldown}
    else
      _ -> :no_gossip
    end
  end

  defp get_valid_entries(set_id, players) do
    Store.get_gossip_entries_for_set(set_id)
    |> Enum.filter(&prerequisite_met?(&1, players))
    |> Enum.sort_by(& &1.indexOrder)
  end

  defp prerequisite_met?(%{prerequisiteId: 0}, _players), do: true
  defp prerequisite_met?(%{prerequisiteId: prereq_id}, players) do
    # Entry shows if ANY nearby player meets prerequisites
    Enum.any?(players, fn player ->
      case PrerequisiteChecker.check(prereq_id, player) do
        {:ok, true} -> true
        _ -> false
      end
    end)
  end

  defp select_random_entry([]), do: nil
  defp select_random_entry(entries), do: Enum.random(entries)

  defp broadcast_gossip(npc, creature, entry, players) do
    packet = %ServerChatNPC{
      channel: %Channel{type: :npc_say, chat_id: 0},
      unit_name_text_id: creature.localizedTextIdName,
      message_text_id: entry.localizedTextId
    }

    Enum.each(players, fn player ->
      send(player.connection_pid, {:send_packet, packet})
    end)
  end
end
```

### Zone Integration

Add gossip checks to zone tick:

```elixir
# In Zone.Instance, during periodic tick
defp tick_ambient_gossip(state) do
  state.npcs
  |> Enum.filter(&has_gossip_set?/1)
  |> Enum.reduce(state, fn npc, acc_state ->
    nearby = get_nearby_players(acc_state, npc.position, 30.0)
    case GossipManager.check_proximity_gossip(npc, nearby, acc_state.gossip_cooldowns) do
      {:cooldown, duration} ->
        put_gossip_cooldown(acc_state, npc.guid, duration)
      :no_gossip ->
        acc_state
    end
  end)
end
```

## Gossip Data Structure

### GossipSet

```json
{
  "ID": 1,
  "flags": 0,
  "gossipProximityEnum": 0,
  "cooldown": 0
}
```

- `flags`: Behavior flags (0 or 1 in data)
- `gossipProximityEnum`: 0=click-only, 1=close, 2=medium range
- `cooldown`: Seconds between ambient triggers

### GossipEntry

```json
{
  "ID": 1,
  "gossipSetId": 1,
  "indexOrder": 0,
  "localizedTextId": 19245,
  "prerequisiteId": 0
}
```

- `indexOrder`: Display order (for sequential dialogue)
- `localizedTextId`: Text to display (client resolves)
- `prerequisiteId`: Condition for showing this entry

## Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `packets/world/server_dialog_start.ex` | Dialog open packet |
| `packets/world/server_chat_npc.ex` | NPC chat packet |
| `gossip_manager.ex` | Ambient gossip logic |

### Modified Files

| File | Changes |
|------|---------|
| `opcode.ex` | Add new opcodes |
| `packet_registry.ex` | Register new packets |
| `handler/npc_handler.ex` | Handle event 37 |
| `zone/instance.ex` | Call gossip tick |

### Unchanged Files

- `Store` - gossip query functions exist
- `PrerequisiteChecker` - reused as-is
- All gossip JSON data files

## Testing Strategy

1. **Unit tests** for packet serialization
2. **Unit tests** for prerequisite filtering
3. **Unit tests** for random entry selection
4. **Integration test** with zone instance
5. **Manual test** with WildStar client

## Complexity Assessment

| Component | Effort | Risk |
|-----------|--------|------|
| ServerDialogStart packet | Low | Low |
| ServerChatNPC packet | Low | Low |
| Click-dialogue handler | Low | Low |
| GossipManager module | Medium | Low |
| Zone tick integration | Low | Low |
| Cooldown tracking | Low | Low |

**Total estimate:** ~200-300 lines of new code

## References

- NexusForever `ClientEntityInteractionHandler.cs`
- NexusForever `ServerDialogStart.cs`
- NexusForever `ServerChatNPC.cs`
- Bezgelor `gossip_entries.json` (10,799 records)
- Bezgelor `gossip_sets.json` (1,978 records)
