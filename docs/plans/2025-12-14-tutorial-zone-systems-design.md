# Tutorial Zone Systems Design

**Date:** 2025-12-14
**Status:** Approved

## Overview

Implement a complete tutorial experience for new players, including trigger-based teleportation, quest-guided progression, NPC interactions, and the intro cinematic.

## Goals

- Players complete tutorial objectives to unlock progression
- Teleport pads move players between tutorial areas when quest-gated conditions are met
- Full intro cinematic plays when entering the tutorial zone
- NPCs provide dialog and quest guidance

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Trigger detection | Event-driven (on movement) | More efficient than polling, fits Elixir's message-passing model |
| Teleport gating | Quest-based | Teaches players "complete objectives → unlock progress" |
| Trigger→action mapping | Quest objective data | Reuses existing data structures, keeps model unified |
| Teleport destinations | World Location IDs | Single ID reference, reuses world_locations.json |
| Cinematic implementation | Full port from NexusForever | Complete tutorial experience as requested |
| NPC interaction | Full system with branching dialogs | Supports tutorial guidance and future content |

## System Components

### 1. Trigger Volume System

**Purpose:** Detect when players enter specific areas to fire events.

**Architecture:**
```
Movement Handler → Zone Instance → Trigger Checker → Event Bus
```

**Components:**

- **TriggerVolume struct** - Holds world_location_id, position, radius, and registered callbacks

- **Zone.Instance enhancement** - Each zone instance loads trigger volumes from `world_locations.json` on init, stored in spatial structure for efficient lookup

- **Trigger check on movement** - When `MovementHandler` processes a position update, calls `Zone.Instance.check_triggers(entity, new_position)` to check if entity entered any new trigger radius

- **Event emission** - When triggered, broadcasts `{:trigger_entered, player_id, world_location_id}` to subscribers

**Data flow:**
```elixir
# In MovementHandler after position update:
Zone.Manager.check_triggers(zone_pid, entity_guid, new_position)

# In Zone.Instance:
def check_triggers(entity_guid, position) do
  entered = find_entered_triggers(entity_guid, position)
  for trigger <- entered do
    EventBus.broadcast({:trigger_entered, entity_guid, trigger.id})
  end
end
```

### 2. Quest-Gated Teleportation

**Purpose:** Teleport players when they complete quest objectives by entering trigger areas.

**Architecture:**
```
Trigger Event → Quest Manager → Objective Update → Quest Complete → Reward Handler → Teleport
```

**Components:**

- **Quest objective subscription** - `QuestManager` subscribes to `{:trigger_entered, _, _}` events, checks for `EnterArea` (type 22) or `EnterZone` (type 17) objectives

- **Objective completion** - Updates objective progress, moves quest to completable state when all objectives done

- **Teleport reward type** - Quest rewards include `teleport_to_world_location` field

- **Teleport execution** - `Teleport` module handles zone transition

**Quest reward example:**
```json
{
  "questId": 8042,
  "rewards": {
    "teleportToWorldLocationId": 1234
  }
}
```

### 3. Teleport Implementation

**Module:** `BezgelorWorld.Teleport`

**Functions:**
```elixir
defmodule BezgelorWorld.Teleport do
  def to_world_location(session, world_location_id)
  def to_position(session, world_id, {x, y, z}, rotation \\ {0, 0, 0})
end
```

**Teleport sequence:**

1. **Validate** - Check world_location exists, player can teleport
2. **Cleanup current zone** - Remove entity, notify nearby players with `ServerEntityDestroy` (reason: teleport)
3. **Update session** - Set new world_id, zone_id, position, rotation
4. **Send transition packets** - `ServerWorldEnter`, `ServerEntityCreate`, init packets
5. **Register in new zone** - Add entity to new zone instance

**Edge cases:**
- Same-zone teleport: Skip world enter, just reposition
- Cross-zone teleport: Full zone transition
- Invalid destination: Log error, don't teleport

### 4. Cinematic System

**Purpose:** Play scripted sequences with actors, camera movement, effects, and timed events.

**Module structure:**
```
BezgelorWorld.Cinematic
├── Cinematic           # Base struct and playback logic
├── Actor               # Spawned entity for cinematic
├── Camera              # Camera control and transitions
├── Keyframe            # Timed action scheduler
├── Text                # Subtitle/dialog display
└── Cinematics
    └── NoviceTutorialOnEnter
```

**Cinematic struct:**
```elixir
defstruct [
  :id,
  :player,              # Player session watching
  :duration,            # Total length in ms
  :actors,              # Map of actor_id => Actor
  :cameras,             # List of Camera structs
  :keyframes,           # List of {timestamp, action}
  :start_time,
  :state                # :pending | :playing | :finished
]
```

**Playback flow:**
1. Initialize cinematic, spawn actors
2. Send `ServerCinematicStart` to lock player controls
3. Start keyframe timer process
4. Execute actions at timestamps (camera, text, VFX)
5. On completion, despawn actors, restore control

### 5. Actor System

**Purpose:** Spawn temporary entities for cinematics.

**Actor struct:**
```elixir
defstruct [
  :id,
  :creature_id,
  :position,
  :rotation,
  :visible,
  :entity_guid
]
```

**Key functions:**
```elixir
Actor.spawn(actor, player_session)
Actor.move(actor, new_position, new_rotation)
Actor.set_visible(actor, visible)
Actor.despawn(actor, player_session)
```

**Player-specific spawning:** Actors only send packets to the cinematic's player session, not broadcast to zone.

### 6. Camera Control

**Camera struct:**
```elixir
defstruct [
  :actor_id,            # Actor to attach to
  :mode,                # :free | :attached | :transition
  :position,
  :target,
  :fov,
  :transitions
]
```

**Packets:**
- `ServerCinematicCameraAttach`
- `ServerCinematicCameraTransition`
- `ServerCinematicCameraPosition`

### 7. Keyframe System

**Purpose:** Schedule actions at specific timestamps.

**Implementation:** GenServer managing timer and action queue.

```elixir
defstruct [
  :cinematic,
  :actions,             # Sorted list of {timestamp_ms, action}
  :start_time,
  :next_timer_ref
]

# Action types:
# {:spawn_actor, actor_id}
# {:move_actor, actor_id, position, rotation}
# {:camera_attach, actor_id}
# {:show_text, text_id, duration}
# {:play_vfx, vfx_id, target}
```

### 8. Text/Subtitle Display

**Text entry:**
```elixir
%{
  text_id: 750164,
  start_ms: 1300,
  end_ms: 5767,
  speaker: :dorian
}
```

**Faction handling:** Different text for Exile (Dorian) vs Dominion (Artemis).

### 9. NPC Interaction System

**Architecture:**
```
ClientNpcInteract → NpcHandler → Interaction Router → Dialog/Quest/Service
```

**Interaction types:**
- Quest giver - NPC offers quests
- Quest turn-in - NPC accepts completed quests
- Dialog - NPC speaks guidance text

**Handler flow:**
```elixir
def handle_npc_interact(creature_id, player) do
  interactions = Store.get_npc_interactions(creature_id)

  case determine_interaction(interactions, player) do
    {:quest_offer, quest_id} -> send_quest_offer(player, quest_id)
    {:quest_turnin, quest_id} -> send_quest_turnin(player, quest_id)
    {:dialog, dialog_id} -> send_dialog(player, dialog_id)
  end
end
```

### 10. Dialog System

**Dialog struct:**
```elixir
defstruct [
  :id,
  :text_id,
  :speaker_name,
  :portrait,
  :responses
]
```

**Response options:**
```elixir
%{
  text_id: 123456,
  action: :continue,      # :continue | :close | :accept_quest
  next_dialog_id: 5679
}
```

**Packets:**
- `ServerNpcDialog` - Show dialog
- `ClientNpcDialogResponse` - Player response
- `ServerNpcDialogClose` - Close dialog

## Tutorial Quest Data

**Quest chain (Exile example):**

| Quest | Objectives | Reward |
|-------|-----------|--------|
| Wake Up | Watch intro cinematic | Unlock movement |
| First Steps | Walk to marker | XP |
| Meet Dorian | Talk to Dorian hologram | Next quest |
| Combat Training | Kill training dummy | Unlock abilities |
| Exit Cryo | Step on teleport pad | Teleport to next area |

**Quest data structure:**
```json
{
  "id": 8042,
  "name": "Exit Cryo Bay",
  "type": "tutorial",
  "autoAccept": true,
  "objectives": [
    {
      "type": 22,
      "data": 4844,
      "count": 1,
      "text": "Step on the teleport pad"
    }
  ],
  "rewards": {
    "xp": 100,
    "teleportToWorldLocationId": 1234
  }
}
```

## Implementation Order

### Phase 1: Core Teleportation
1. `Teleport` module with `to_world_location/2`
2. Zone transition packets
3. Test with `/teleport` command

### Phase 2: Trigger Volumes
4. Trigger volume loading in Zone.Instance
5. Movement handler integration
6. Event emission on trigger entry
7. Test by walking into trigger areas

### Phase 3: Quest Integration
8. Quest objective type handlers for EnterArea/EnterZone
9. Teleport reward type
10. Tutorial quest data files
11. Quest auto-accept for tutorial zones
12. Test full flow: spawn → walk to pad → teleport

### Phase 4: NPC Interaction
13. NpcHandler for ClientNpcInteract
14. Dialog system packets
15. Quest offer/turn-in UI
16. Test talking to NPCs

### Phase 5: Cinematics
17. Actor spawning
18. Keyframe scheduler
19. Camera control
20. Text display
21. NoviceTutorialOnEnter cinematic
22. Test full tutorial intro

## Success Criteria

- [ ] New character spawns in tutorial zone
- [ ] Intro cinematic plays automatically
- [ ] Tutorial quests auto-accept and guide player
- [ ] NPCs respond to interaction with dialogs
- [ ] Completing objectives unlocks teleport pads
- [ ] Stepping on pad teleports to next area
- [ ] Player can complete full tutorial and reach main world
