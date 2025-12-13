# Quest System Implementation Plan

**Date:** 2025-12-12
**Status:** Ready for Implementation
**Scope:** Wire all 5,194 quests with event-driven objective tracking

## Executive Summary

The quest system infrastructure is **80% complete**. Core handlers, packets, and event routing exist but use a DB-per-event approach that's inefficient. This plan adds session caching and participant-based credit to complete the system.

## Current State Analysis

### What Already Exists

| Component | File | Status |
|-----------|------|--------|
| QuestHandler | `apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex` | ✅ Accept/abandon/turn-in, process_kill |
| ObjectiveHandler | `apps/bezgelor_world/lib/bezgelor_world/quest/objective_handler.ex` | ✅ All 20 objective types mapped |
| CombatBroadcaster | `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex` | ✅ notify_creature_kill, notify_item_loot, etc. |
| SpellHandler | `apps/bezgelor_world/lib/bezgelor_world/handler/spell_handler.ex` | ✅ Calls notify_creature_kill on death |
| Quest packets | `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/` | ✅ ServerQuestAdd/Update/Remove/List |
| DB storage | `apps/bezgelor_db/lib/bezgelor_db/quests.ex` | ✅ JSON progress, history tracking |
| Quest data | `apps/bezgelor_data/priv/data/` | ✅ 5,194 quests, 10,031 objectives |

### Current Event Flow

```
Creature dies → SpellHandler
  → CombatBroadcaster.notify_creature_kill()
    → ObjectiveHandler.process_event(:kill, ...)
      → Quests.get_active_quests(character_id)  ← DB QUERY EVERY EVENT
      → QuestHandler.increment_objective()
        → Quests.update_objective()  ← DB WRITE EVERY UPDATE
        → send(connection_pid, {:send_packet, packet})
```

### What's Missing

| Gap | Impact | Priority |
|-----|--------|----------|
| Session quest caching | DB query on every event = slow | HIGH |
| Participant-based credit | Only killer gets quest credit | HIGH |
| Load quests on login | session_data.active_quests empty | HIGH |
| Periodic persistence | DB write on every objective | MEDIUM |
| Group credit sharing | Group members don't get credit | MEDIUM |

## Architecture Design (from Brainstorm)

### Session Data Structure

```elixir
session_data = %{
  # ...existing fields...

  active_quests: %{
    101 => %{
      quest_id: 101,
      state: :in_progress,
      accepted_at: ~U[2025-12-12 10:00:00Z],
      objectives: [
        %{index: 0, type: 2, data: 12345, current: 3, target: 10},
        %{index: 1, type: 3, data: 67890, current: 0, target: 5}
      ]
    }
  },

  completed_quest_ids: MapSet.new([1, 2, 3, ...])
}
```

### Target Event Flow

```
Creature dies → Zone.Instance
  → get_kill_credit_participants(creature_guid)
  → for player_pid <- participants do
      send(player_pid, {:game_event, :creature_killed, %{creature_id: ...}})
    end

Connection.handle_info({:game_event, :creature_killed, data}, state)
  → for {quest_id, quest} <- session_data.active_quests do
      for obj <- quest.objectives do
        if matches?(obj, :kill, data.creature_id) do
          update_objective_in_session()
          send_quest_update_packet()
          mark_dirty_for_persistence()
        end
      end
    end
```

## Implementation Tasks

### Phase 1: Session Quest Caching (Foundation)

#### Task 1.1: Add Quest State to Session Data
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex`

- [ ] Add `active_quests: %{}` to initial session_data in `ranch_init/1`
- [ ] Add `completed_quest_ids: MapSet.new()` to session_data
- [ ] Add `quest_dirty: false` flag for persistence tracking

**Test:** Unit test that session_data initializes with empty quest state

#### Task 1.2: Create QuestCache Module
**File:** `apps/bezgelor_world/lib/bezgelor_world/quest/quest_cache.ex` (NEW)

- [ ] `load_quests_for_character/1` - Load from DB, convert to cache format
- [ ] `to_session_format/1` - Convert Quest schema to session map
- [ ] `from_session_format/1` - Convert session map back to Quest for DB
- [ ] `mark_dirty/2` - Mark quest as needing persistence
- [ ] `get_dirty_quests/1` - Get quests that need saving

**Test:** Unit tests for format conversion roundtrip

#### Task 1.3: Load Quests on World Entry
**File:** `apps/bezgelor_world/lib/bezgelor_world/handler/world_entry_handler.ex`

- [ ] After character selection, call `QuestCache.load_quests_for_character/1`
- [ ] Store in session_data.active_quests
- [ ] Load completed quest IDs into session_data.completed_quest_ids
- [ ] Send `ServerQuestList` packet to client

**Test:** Integration test that quests load on login

### Phase 2: Session-Based Objective Tracking

#### Task 2.1: Create SessionQuestManager Module
**File:** `apps/bezgelor_world/lib/bezgelor_world/quest/session_quest_manager.ex` (NEW)

- [ ] `process_game_event/3` - Check session quests for matching objectives
- [ ] `update_objective/4` - Update objective in session_data
- [ ] `check_quest_completable/2` - Check if all objectives met
- [ ] `accept_quest/3` - Add quest to session (and DB)
- [ ] `abandon_quest/3` - Remove from session (and DB)
- [ ] `turn_in_quest/3` - Complete quest, grant rewards

**Test:** Unit tests for each function with mock session_data

#### Task 2.2: Add handle_info for Game Events
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex`

- [ ] Add `handle_info({:game_event, event_type, data}, state)` clause
- [ ] Delegate to `SessionQuestManager.process_game_event/3`
- [ ] Return updated state with modified session_data

**Test:** Integration test that Connection receives and processes game events

#### Task 2.3: Update CombatBroadcaster to Use Session Pattern
**File:** `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex`

- [ ] Modify `notify_creature_kill/4` to send `{:game_event, ...}` to connection_pid
- [ ] Remove direct `ObjectiveHandler.process_event` call
- [ ] Update other notify_* functions similarly

**Test:** Verify events are sent as messages, not function calls

### Phase 3: Participant-Based Kill Credit (A3)

#### Task 3.1: Track Combat Participation
**File:** `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex` or `zone/instance.ex`

- [ ] Track `damage_sources: %{player_guid => damage_amount}` per creature
- [ ] Track "tagger" (first player to damage)
- [ ] Function `get_kill_credit_participants/1` returns tagger + their group

**Test:** Unit test that participation is tracked correctly

#### Task 3.2: Implement Group Credit Sharing
**File:** `apps/bezgelor_world/lib/bezgelor_world/group_manager.ex` (if exists, or create)

- [ ] `get_group_members/1` - Get GUIDs of all group members
- [ ] `is_in_group?/2` - Check if two players are grouped
- [ ] Integration with kill credit calculation

**Test:** Test that group members receive credit

#### Task 3.3: Update Death Handling to Broadcast to Participants
**File:** `apps/bezgelor_world/lib/bezgelor_world/creature_death.ex` or caller

- [ ] After creature death, get participants via `get_kill_credit_participants/1`
- [ ] Broadcast `{:game_event, :creature_killed, ...}` to each participant
- [ ] Include creature_id in event data

**Test:** Integration test that all participants receive kill event

### Phase 4: Persistence Layer

#### Task 4.1: Periodic Quest Persistence
**File:** `apps/bezgelor_world/lib/bezgelor_world/quest/quest_persistence.ex` (NEW)

- [ ] `persist_dirty_quests/1` - Save all dirty quests to DB
- [ ] `schedule_persistence/0` - Schedule periodic saves (every 30s)
- [ ] Called from Connection on timer or via GenServer

**Test:** Test that dirty quests are persisted

#### Task 4.2: Persist on Logout/Disconnect
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex`

- [ ] In `handle_info({:tcp_closed, ...})`, call `QuestPersistence.persist_dirty_quests/1`
- [ ] In `handle_info({:tcp_error, ...})`, same
- [ ] Ensure graceful shutdown persists quest state

**Test:** Test that quests persist on disconnect

#### Task 4.3: Persist on Quest State Changes
**File:** `apps/bezgelor_world/lib/bezgelor_world/quest/session_quest_manager.ex`

- [ ] After accept_quest, immediately persist (important state)
- [ ] After turn_in_quest, immediately persist and add to history
- [ ] Objective updates mark dirty but don't persist immediately

**Test:** Test immediate vs deferred persistence

### Phase 5: Quest Acceptance Flow

#### Task 5.1: Wire NPC Quest Givers
**File:** `apps/bezgelor_world/lib/bezgelor_world/handler/npc_handler.ex`

- [ ] On NPC click, check if NPC has quests to give (`questIdGiven00-24` fields)
- [ ] Check prerequisites via `PrerequisiteChecker`
- [ ] Send `ServerQuestOffer` packet for available quests

**Test:** Test that clicking quest giver shows available quests

#### Task 5.2: Handle Quest Accept from Client
**File:** `apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex`

- [ ] Update `handle_accept_packet` to use `SessionQuestManager.accept_quest`
- [ ] Add quest to session_data.active_quests
- [ ] Send `ServerQuestAdd` packet

**Test:** Test full accept flow

#### Task 5.3: Handle Quest Turn-In
**File:** `apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex`

- [ ] Update `handle_turn_in_packet` to use `SessionQuestManager.turn_in_quest`
- [ ] Verify quest is completable (all objectives met)
- [ ] Grant rewards via `RewardHandler`
- [ ] Remove from session, add to completed_quest_ids
- [ ] Send `ServerQuestRemove` packet

**Test:** Test full turn-in flow with rewards

### Phase 6: Testing & Validation

#### Task 6.1: Data Integrity Tests
**File:** `apps/bezgelor_data/test/quest_data_integrity_test.exs` (NEW)

- [ ] All quest objectives have valid creature/item/zone IDs
- [ ] All quest rewards reference valid items
- [ ] Quest chains have valid prerequisite references
- [ ] No orphaned objective data

#### Task 6.2: Integration Tests
**File:** `apps/bezgelor_world/test/integration/quest_integration_test.exs` (NEW)

- [ ] Full flow: Login → Accept quest → Kill creature → Progress updates → Turn in
- [ ] Group credit: Two grouped players, one kills, both get credit
- [ ] Persistence: Disconnect and reconnect, quest state preserved

#### Task 6.3: Packet Validation
**File:** `apps/bezgelor_protocol/test/packets/quest_packets_test.exs` (NEW)

- [ ] ServerQuestAdd serializes correctly
- [ ] ServerQuestUpdate serializes correctly
- [ ] ServerQuestList serializes correctly
- [ ] Compare against captured packets from NexusForever (if available)

## File Summary

### New Files

| File | Purpose |
|------|---------|
| `quest/quest_cache.ex` | Load/convert quests for session |
| `quest/session_quest_manager.ex` | Session-based quest operations |
| `quest/quest_persistence.ex` | Periodic/logout persistence |
| `test/quest_data_integrity_test.exs` | Data validation |
| `test/integration/quest_integration_test.exs` | E2E tests |

### Modified Files

| File | Changes |
|------|---------|
| `connection.ex` | Add handle_info for game events, quest state in session |
| `combat_broadcaster.ex` | Send events as messages instead of function calls |
| `creature_death.ex` | Broadcast to participants |
| `world_entry_handler.ex` | Load quests on login |
| `quest_handler.ex` | Use SessionQuestManager |
| `npc_handler.ex` | Quest giver interaction |

## Dependencies Between Tasks

```
Phase 1 (Foundation)
  1.1 Session Data ─────┐
  1.2 QuestCache ───────┼──► Phase 2 (Tracking)
  1.3 Load on Login ────┘      2.1 SessionQuestManager
                               2.2 handle_info
                               2.3 Update Broadcaster ──► Phase 3 (Participants)
                                                            3.1 Track Participation
                                                            3.2 Group Credit
                                                            3.3 Broadcast Deaths
                                                                    │
                                                                    ▼
                                                          Phase 4 (Persistence)
                                                            4.1 Periodic
                                                            4.2 On Logout
                                                            4.3 On State Change
                                                                    │
                                                                    ▼
                                                          Phase 5 (Accept/Turn-in)
                                                            5.1 Quest Givers
                                                            5.2 Accept
                                                            5.3 Turn-in
                                                                    │
                                                                    ▼
                                                          Phase 6 (Testing)
```

## Success Criteria

1. **Performance:** Quest objective updates don't hit DB (session-cached)
2. **Correctness:** All 20 objective types trigger correctly
3. **Multiplayer:** Group members share kill credit
4. **Persistence:** Quest state survives disconnect/reconnect
5. **Data Coverage:** All 5,194 quests can be accepted/completed

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Session state lost on crash | Quest progress lost | Periodic persistence every 30s |
| Packet format mismatch | Client errors | Compare with NexusForever captures |
| Objective type gaps | Some quests non-functional | Comprehensive type mapping in ObjectiveHandler |
| Group system complexity | Credit sharing bugs | Start with solo credit, add group later |

## Notes

- The existing `ObjectiveHandler` already maps all 20 objective types - reuse this logic
- `PrerequisiteChecker` and `RewardHandler` exist and work - no changes needed
- Quest data is complete (5,194 quests, 10,031 objectives) - no extraction needed
- Focus is on **wiring**, not content creation
