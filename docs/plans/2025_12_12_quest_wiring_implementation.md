# Quest Wiring Implementation Plan

**Date:** 2025-12-12
**Status:** ✅ COMPLETE - All Batches Finished
**Scope:** Full quest system wiring across all zones

## Overview

Wire the extracted quest data (5,194 quests, 10,031 objectives) to the existing quest system infrastructure. This includes creating NPC interaction hooks, implementing all objective types, and completing reward granting.

## Implementation Status

| Component | Status |
|-----------|--------|
| Quest schemas | ✅ Complete |
| Quest context (BezgelorDb.Quests) | ✅ Complete |
| Quest handler | ✅ Complete - Handler behaviour implemented |
| Quest data in ETS | ✅ Loaded |
| Creature→Quest mappings | ✅ Data exists in creatures_full |
| Store query functions | ✅ Complete |
| NPC interaction system | ✅ Complete |
| Objective type handlers | ✅ Complete - 15 event types supported |
| Reward granting | ✅ Complete |
| Packet registration | ✅ Complete |
| Session-based tracking | ✅ Complete - SessionQuestManager |
| Quest persistence | ✅ Complete - Periodic + logout |
| Integration tests | ✅ Complete - 80 tests passing |
| Packet validation tests | ✅ Complete |

## Completed Tasks

### Batch 1-2: Session Quest Management
- ✅ Task 1.1: Add Quest State to Session Data (connection.ex)
- ✅ Task 1.2: Create QuestCache Module
- ✅ Task 1.3: Load Quests on World Entry
- ✅ Task 2.1: Create SessionQuestManager Module
- ✅ Task 2.2: Add handle_info for Game Events
- ✅ Task 2.3: Update CombatBroadcaster to Use Session Pattern

### Batch 3: Combat Kill Credit
- ✅ Task 3.1: Track Combat Participation
- ✅ Task 3.2: Implement Group Credit Sharing
- ✅ Task 3.3: Update Death Handling to Broadcast to Participants

### Batch 4: Quest Persistence
- ✅ Task 4.1: Periodic Quest Persistence (every 30 seconds)
- ✅ Task 4.2: Persist on Logout/Disconnect
- ✅ Task 4.3: Persist on Quest State Changes

### Batch 5: Handler Wiring
- ✅ Task 5.1: Wire NPC Quest Givers
- ✅ Task 5.2: Handle Quest Accept from Client
- ✅ Task 5.3: Handle Quest Turn-In

### Batch 6: Testing
- ✅ Task 6.1: Data Integrity Tests (quest_handler_test.exs)
- ✅ Task 6.2: Integration Tests (quest_integration_test.exs)
- ✅ Task 6.3: Packet Validation Tests (quest_packets_test.exs)

## Test Results

- `apps/bezgelor_world/test/quest/` - 55 tests, 0 failures
- `apps/bezgelor_protocol/test/packets/quest_packets_test.exs` - 25 tests, 0 failures
- **Total: 80 tests passing**

---

## Quest Flow Architecture

The quest system follows this packet flow:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        QUEST OFFER FLOW                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Player right-clicks NPC                                             │
│         │                                                            │
│         ▼                                                            │
│  ClientNpcInteract packet ──────────────────────────────────────────▶│
│         │                                                            │
│         ▼                                                            │
│  NpcHandler.handle/2 (BezgelorProtocol.Handler behaviour)            │
│         │                                                            │
│         ▼                                                            │
│  PacketReader.new(payload)                                           │
│  ClientNpcInteract.read(reader)                                      │
│         │                                                            │
│         ▼                                                            │
│  handle_interact(connection_pid, character_id, packet, session_data) │
│         │                                                            │
│         ▼                                                            │
│  extract_creature_id(npc_guid, session_data)                         │
│         │                                                            │
│         ├── Store.creature_quest_giver?(creature_id)                 │
│         │         │                                                  │
│         │         ▼                                                  │
│         │   handle_quest_giver(...)                                  │
│         │         │                                                  │
│         │         ▼                                                  │
│         │   Store.get_quests_for_creature_giver(creature_id)         │
│         │         │                                                  │
│         │         ▼                                                  │
│         │   Filter by PrerequisiteChecker.can_accept_quest?/2        │
│         │         │                                                  │
│         │         ▼                                                  │
│         │   ServerQuestOffer packet ─────────────────────────────────▶│
│         │                                                            │
│         ├── Store.get_vendor_by_creature(creature_id)                │
│         │         ▼                                                  │
│         │   handle_vendor(...)                                       │
│         │                                                            │
│         └── handle_generic_npc(...) [gossip, trainers]               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      QUEST ACCEPT FLOW                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Player clicks "Accept" in quest dialog                              │
│         │                                                            │
│         ▼                                                            │
│  ClientAcceptQuest packet (quest_id, npc_guid) ─────────────────────▶│
│         │                                                            │
│         ▼                                                            │
│  QuestHandler.handle/2 (BezgelorProtocol.Handler behaviour)          │
│         │                                                            │
│         ▼                                                            │
│  state[:current_opcode] == :client_accept_quest                      │
│         │                                                            │
│         ▼                                                            │
│  handle_accept_packet(reader, state)                                 │
│         │                                                            │
│         ▼                                                            │
│  ClientAcceptQuest.read(reader)                                      │
│         │                                                            │
│         ▼                                                            │
│  Store.get_quest_with_objectives(quest_id)                           │
│         │                                                            │
│         ▼                                                            │
│  handle_accept_quest(connection_pid, character_id, packet, quest_data)│
│         │                                                            │
│         ▼                                                            │
│  Quests.init_progress(objectives)                                    │
│         │                                                            │
│         ▼                                                            │
│  Quests.accept_quest(character_id, quest_id, progress: progress)     │
│         │                                                            │
│         ├── {:ok, quest} ──▶ ServerQuestAdd packet ─────────────────▶│
│         │                                                            │
│         └── {:error, :quest_log_full} ──▶ Error handling             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      QUEST TURN-IN FLOW                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Player clicks "Complete" at quest receiver NPC                      │
│         │                                                            │
│         ▼                                                            │
│  ClientTurnInQuest packet (quest_id, npc_guid, reward_choice) ──────▶│
│         │                                                            │
│         ▼                                                            │
│  QuestHandler.handle/2                                               │
│         │                                                            │
│         ▼                                                            │
│  state[:current_opcode] == :client_turn_in_quest                     │
│         │                                                            │
│         ▼                                                            │
│  handle_turn_in_packet(reader, state)                                │
│         │                                                            │
│         ▼                                                            │
│  handle_turn_in_quest(connection_pid, character_id, packet)          │
│         │                                                            │
│         ▼                                                            │
│  Quests.turn_in_quest(character_id, quest_id)                        │
│         │                                                            │
│         ├── {:ok, _history}                                          │
│         │         │                                                  │
│         │         ▼                                                  │
│         │   ServerQuestRemove packet (reason: :completed) ──────────▶│
│         │         │                                                  │
│         │         ▼                                                  │
│         │   RewardHandler.grant_quest_rewards(pid, char_id, quest_id)│
│         │         │                                                  │
│         │         ├── XP grant                                       │
│         │         ├── Gold grant                                     │
│         │         ├── Item grants                                    │
│         │         └── Reputation grants                              │
│         │                                                            │
│         └── {:error, :not_complete} ──▶ Error handling               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `handler_registration.ex` | Registers packet → handler mappings |
| `quest_handler.ex` | Implements `BezgelorProtocol.Handler` for quest packets |
| `npc_handler.ex` | Implements `BezgelorProtocol.Handler` for NPC interaction |
| `store.ex` | Quest data queries from ETS |
| `quests.ex` | Database operations (accept, turn_in, progress) |
| `prerequisite_checker.ex` | Quest eligibility validation |
| `reward_handler.ex` | XP, gold, item, reputation grants |

## Packet Registration

Located in `apps/bezgelor_world/lib/bezgelor_world/handler_registration.ex`:

```elixir
# NPC interaction
PacketRegistry.register(:client_npc_interact, NpcHandler)

# Quests
PacketRegistry.register(:client_accept_quest, QuestHandler)
PacketRegistry.register(:client_abandon_quest, QuestHandler)
PacketRegistry.register(:client_turn_in_quest, QuestHandler)
PacketRegistry.register(:client_quest_share, QuestHandler)
```

---

## Implementation Phases

---

### Phase 1: Data Store Query Functions

**Goal:** Enable querying quests by creature giver/receiver

**Files:**
- `apps/bezgelor_data/lib/bezgelor_data/store.ex`

**Tasks:**

1.1. Add `get_quests_for_creature_giver/1`
```elixir
@doc "Get quest IDs that a creature can give"
@spec get_quests_for_creature_giver(non_neg_integer()) :: [non_neg_integer()]
def get_quests_for_creature_giver(creature_id) do
  case get_creature_full(creature_id) do
    {:ok, creature} ->
      # Extract non-zero questIdGiven00-24 fields
      0..24
      |> Enum.map(&Map.get(creature, String.to_atom("questIdGiven#{String.pad_leading(Integer.to_string(&1), 2, "0")}")))
      |> Enum.reject(&(&1 == 0 or is_nil(&1)))
    :error -> []
  end
end
```

1.2. Add `get_quests_for_creature_receiver/1`
```elixir
@doc "Get quest IDs that a creature can receive turn-ins for"
@spec get_quests_for_creature_receiver(non_neg_integer()) :: [non_neg_integer()]
def get_quests_for_creature_receiver(creature_id) do
  case get_creature_full(creature_id) do
    {:ok, creature} ->
      # Extract non-zero questIdReceive00-24 fields
      0..24
      |> Enum.map(&Map.get(creature, String.to_atom("questIdReceive#{String.pad_leading(Integer.to_string(&1), 2, "0")}")))
      |> Enum.reject(&(&1 == 0 or is_nil(&1)))
    :error -> []
  end
end
```

1.3. Add `get_quest_with_objectives/1`
```elixir
@doc "Get quest definition with all objective definitions included"
@spec get_quest_with_objectives(non_neg_integer()) :: {:ok, map()} | :error
def get_quest_with_objectives(quest_id) do
  case get(:quests, quest_id) do
    {:ok, quest} ->
      objectives =
        0..5
        |> Enum.map(&Map.get(quest, String.to_atom("objective#{&1}")))
        |> Enum.reject(&(&1 == 0 or is_nil(&1)))
        |> Enum.map(&get(:quest_objectives, &1))
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, obj} -> obj end)
      {:ok, Map.put(quest, :objectives, objectives)}
    :error -> :error
  end
end
```

1.4. Add `get_creature_quest_giver?/1`
```elixir
@doc "Check if creature is a quest giver"
@spec creature_quest_giver?(non_neg_integer()) :: boolean()
def creature_quest_giver?(creature_id) do
  get_quests_for_creature_giver(creature_id) != []
end
```

1.5. Add `get_creature_quest_receiver?/1`
```elixir
@doc "Check if creature is a quest receiver"
@spec creature_quest_receiver?(non_neg_integer()) :: boolean()
def creature_quest_receiver?(creature_id) do
  get_quests_for_creature_receiver(creature_id) != []
end
```

**Tests:**
- `apps/bezgelor_data/test/store_quest_test.exs`

---

### Phase 2: NPC Interaction System

**Goal:** Create entry point for player→NPC interaction that triggers quest offering

**Files:**
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_npc_interact.ex` (new)
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_quest_offer.ex` (new)
- `apps/bezgelor_world/lib/bezgelor_world/handler/npc_handler.ex` (new or extend)

**Tasks:**

2.1. Create `ClientNpcInteract` packet
```elixir
defmodule BezgelorProtocol.Packets.World.ClientNpcInteract do
  @moduledoc "Client requests interaction with NPC"
  use BezgelorProtocol.Packet

  @type t :: %__MODULE__{
    target_guid: non_neg_integer()
  }

  defstruct [:target_guid]

  @impl Readable
  def read(data) do
    with {:ok, target_guid, rest} <- PacketReader.read_uint64(data) do
      {:ok, %__MODULE__{target_guid: target_guid}, rest}
    end
  end
end
```

2.2. Create `ServerQuestOffer` packet
```elixir
defmodule BezgelorProtocol.Packets.World.ServerQuestOffer do
  @moduledoc "Server offers available quests from NPC"
  use BezgelorProtocol.Packet

  @type t :: %__MODULE__{
    npc_guid: non_neg_integer(),
    quests: [quest_offer()]
  }

  @type quest_offer :: %{
    quest_id: non_neg_integer(),
    title_text_id: non_neg_integer(),
    level: non_neg_integer(),
    state: :available | :in_progress | :ready_to_turn_in
  }

  defstruct [:npc_guid, :quests]

  @impl Writable
  def write(%__MODULE__{} = packet) do
    # ... binary encoding
  end
end
```

2.3. Create `NpcHandler` module
```elixir
defmodule BezgelorWorld.Handler.NpcHandler do
  @moduledoc "Handles NPC interactions"

  alias BezgelorData.Store
  alias BezgelorDb.Quests

  def handle_interact(connection_pid, character_id, %ClientNpcInteract{target_guid: guid}) do
    creature_id = extract_creature_id(guid)

    with true <- Store.creature_quest_giver?(creature_id) or Store.creature_quest_receiver?(creature_id),
         quest_offers <- build_quest_offers(character_id, creature_id) do
      send_quest_offer(connection_pid, guid, quest_offers)
    else
      false -> handle_non_quest_npc(connection_pid, creature_id)
    end
  end

  defp build_quest_offers(character_id, creature_id) do
    giveable = Store.get_quests_for_creature_giver(creature_id)
    receivable = Store.get_quests_for_creature_receiver(creature_id)
    active_quests = Quests.get_active_quests(character_id) |> Enum.map(& &1.quest_id)
    completed_quests = Quests.get_completed_quest_ids(character_id)

    # Build offer list with states
    giveable
    |> Enum.map(fn quest_id ->
      cond do
        quest_id in active_quests ->
          if quest_id in receivable and quest_ready_to_turn_in?(character_id, quest_id),
            do: %{quest_id: quest_id, state: :ready_to_turn_in},
            else: %{quest_id: quest_id, state: :in_progress}
        quest_id in completed_quests -> nil  # Already done, skip unless repeatable
        can_accept_quest?(character_id, quest_id) -> %{quest_id: quest_id, state: :available}
        true -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
```

2.4. Register packet handler
- Add to packet registry
- Wire to connection handler

**Tests:**
- `apps/bezgelor_world/test/handler/npc_handler_test.exs`

---

### Phase 3: Quest Prerequisite Validation

**Goal:** Validate all quest prerequisites before acceptance

**Files:**
- `apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex`
- `apps/bezgelor_db/lib/bezgelor_db/quests.ex`

**Tasks:**

3.1. Implement full `can_accept_quest?/2`
```elixir
def can_accept_quest?(character_id, quest_id) do
  with {:ok, quest} <- Store.get_quest(quest_id),
       {:ok, character} <- Characters.get_character(character_id),
       :ok <- check_level_requirement(character, quest),
       :ok <- check_race_requirement(character, quest),
       :ok <- check_class_requirement(character, quest),
       :ok <- check_faction_requirements(character, quest),
       :ok <- check_quest_prerequisites(character_id, quest),
       :ok <- check_not_already_active(character_id, quest_id),
       :ok <- check_not_completed_unless_repeatable(character_id, quest) do
    true
  else
    {:error, _reason} -> false
  end
end

defp check_level_requirement(character, quest) do
  if quest.preq_level == 0 or character.level >= quest.preq_level,
    do: :ok,
    else: {:error, :level_too_low}
end

defp check_race_requirement(character, quest) do
  if quest.preq_race == 0 or character.race_id == quest.preq_race,
    do: :ok,
    else: {:error, :wrong_race}
end

defp check_class_requirement(character, quest) do
  if quest.preq_class == 0 or character.class_id == quest.preq_class,
    do: :ok,
    else: {:error, :wrong_class}
end

defp check_faction_requirements(character, quest) do
  # Check factionIdPreq0-2 and factionLevelPreq0-2
  # ... implementation
end

defp check_quest_prerequisites(character_id, quest) do
  prereqs = [quest.preq_quest0, quest.preq_quest1, quest.preq_quest2]
    |> Enum.reject(&(&1 == 0))

  completed = Quests.get_completed_quest_ids(character_id)

  if Enum.all?(prereqs, &(&1 in completed)),
    do: :ok,
    else: {:error, :missing_prereq_quest}
end
```

**Tests:**
- `apps/bezgelor_world/test/handler/quest_handler_test.exs`

---

### Phase 4: Objective Type Handlers

**Goal:** Implement handlers for all 48+ objective types

**Files:**
- `apps/bezgelor_world/lib/bezgelor_world/handler/quest_objective_handler.ex` (new)

**Objective Type Mapping (from quest_objectives.json analysis):**

| Type | Name | Count | Handler |
|------|------|-------|---------|
| 2 | Kill Creature | 598 | `process_kill/3` |
| 4 | Collect Item | 327 | `process_item_collect/4` |
| 5 | Interact Object | 1,556 | `process_interact/3` |
| 12 | Visit Location | 1,187 | `process_location/4` |
| 38 | Unknown/Special | 2,520 | `process_special/3` |
| 1 | Talk to NPC | ~200 | `process_talk/3` |
| 3 | Deliver Item | ~150 | `process_deliver/4` |
| 8 | Use Ability | ~100 | `process_ability/3` |
| ... | (40+ more types) | ... | ... |

**Tasks:**

4.1. Create `QuestObjectiveHandler` module
```elixir
defmodule BezgelorWorld.Handler.QuestObjectiveHandler do
  @moduledoc "Handles quest objective progress for all objective types"

  alias BezgelorData.Store
  alias BezgelorDb.Quests

  # Type constants from client data
  @type_kill 2
  @type_deliver 3
  @type_collect 4
  @type_interact 5
  @type_use_ability 8
  @type_visit_location 12
  @type_special 38
  # ... all 48+ types

  @doc "Process an event and update matching quest objectives"
  def process_event(character_id, event_type, event_data) do
    active_quests = Quests.get_active_quests(character_id)

    for quest <- active_quests do
      process_quest_objectives(character_id, quest, event_type, event_data)
    end
  end

  defp process_quest_objectives(character_id, quest, event_type, event_data) do
    {:ok, quest_def} = Store.get_quest_with_objectives(quest.quest_id)

    quest_def.objectives
    |> Enum.with_index()
    |> Enum.each(fn {objective, index} ->
      if matches_event?(objective, event_type, event_data) do
        increment_objective(character_id, quest, index, objective)
      end
    end)
  end

  defp matches_event?(%{type: @type_kill, data: creature_id}, :kill, %{creature_id: killed_id}) do
    creature_id == killed_id
  end

  defp matches_event?(%{type: @type_collect, data: item_id}, :collect, %{item_id: collected_id}) do
    item_id == collected_id
  end

  defp matches_event?(%{type: @type_interact, data: object_id}, :interact, %{object_id: interacted_id}) do
    object_id == interacted_id
  end

  defp matches_event?(%{type: @type_visit_location, data: location_id}, :enter_area, %{area_id: area}) do
    location_id == area
  end

  # ... handlers for all 48+ types

  defp matches_event?(_, _, _), do: false
end
```

4.2. Hook into game events
- Kill events from combat system
- Item pickup events from inventory
- Object interaction events
- Area entry events from zone system
- Ability use events from spell system

4.3. Implement all objective types
```elixir
# Full type list to implement:
@objective_types %{
  1 => :talk_to_npc,
  2 => :kill_creature,
  3 => :deliver_item,
  4 => :collect_item,
  5 => :interact_object,
  6 => :use_item,
  7 => :equip_item,
  8 => :use_ability,
  9 => :complete_event,
  10 => :win_pvp,
  11 => :complete_challenge,
  12 => :visit_location,
  13 => :craft_item,
  14 => :gather_resource,
  15 => :discover_area,
  16 => :earn_achievement,
  17 => :reach_level,
  18 => :gain_reputation,
  19 => :complete_path_mission,
  20 => :activate_datacube,
  21 => :scan_creature,
  22 => :capture_point,
  23 => :escort_npc,
  24 => :defend_object,
  25 => :survive_waves,
  # ... continue for all 48+ types
  38 => :special_scripted
}
```

**Tests:**
- `apps/bezgelor_world/test/handler/quest_objective_handler_test.exs`

---

### Phase 5: Reward Granting

**Goal:** Complete implementation of all reward types

**Files:**
- `apps/bezgelor_world/lib/bezgelor_world/handler/quest_handler.ex`

**Tasks:**

5.1. Implement `grant_quest_rewards/2`
```elixir
def grant_quest_rewards(character_id, quest_id) do
  {:ok, quest} = Store.get_quest(quest_id)
  rewards = Store.get_quest_rewards(quest_id)

  # Grant XP
  xp_amount = calculate_xp(quest)
  XpHandler.grant_xp(character_id, xp_amount, :quest)

  # Grant currency (gold)
  gold_amount = calculate_gold(quest)
  Inventory.add_currency(character_id, :gold, gold_amount)

  # Grant pushed items (guaranteed rewards)
  grant_pushed_items(character_id, quest)

  # Grant chosen rewards (from quest_rewards)
  grant_choice_rewards(character_id, rewards)

  # Grant reputation
  grant_reputation_rewards(character_id, quest)

  :ok
end

defp calculate_xp(quest) do
  if quest.reward_xpOverride > 0 do
    quest.reward_xpOverride
  else
    # Base XP formula based on quest level
    base_xp = quest.conLevel * 100
    base_xp
  end
end

defp grant_pushed_items(character_id, quest) do
  0..5
  |> Enum.each(fn i ->
    item_id = Map.get(quest, String.to_atom("pushed_itemId#{i}"))
    count = Map.get(quest, String.to_atom("pushed_itemCount#{i}"))

    if item_id && item_id > 0 && count && count > 0 do
      Inventory.add_item(character_id, item_id, count)
    end
  end)
end

defp grant_choice_rewards(character_id, rewards) do
  # Filter for choice rewards (type 1)
  # Client should have sent chosen reward ID
  # For now, grant first available choice
  rewards
  |> Enum.filter(&(&1.quest2RewardTypeId == 1))
  |> Enum.take(1)
  |> Enum.each(fn reward ->
    Inventory.add_item(character_id, reward.objectId, reward.objectAmount)
  end)
end
```

5.2. Implement reward choice packet
```elixir
defmodule BezgelorProtocol.Packets.World.ClientQuestRewardChoice do
  @moduledoc "Client chooses reward from multiple options"
  # ... implementation
end
```

**Tests:**
- `apps/bezgelor_world/test/handler/quest_reward_test.exs`

---

### Phase 6: Integration & Testing

**Goal:** End-to-end quest flow validation

**Tasks:**

6.1. Integration test: Full quest lifecycle
```elixir
defmodule BezgelorWorld.QuestIntegrationTest do
  # Test: Player talks to NPC → sees quest → accepts → completes objectives → turns in → gets rewards
end
```

6.2. Validate all 5,194 quests load correctly
6.3. Validate objective type coverage
6.4. Load test with multiple concurrent players

---

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `store.ex` | Modify | Add 5 query functions |
| `client_npc_interact.ex` | Create | NPC interaction packet |
| `server_quest_offer.ex` | Create | Quest offer packet |
| `npc_handler.ex` | Create | NPC interaction handler |
| `quest_handler.ex` | Modify | Prerequisites, rewards |
| `quest_objective_handler.ex` | Create | All objective types |
| `client_quest_reward_choice.ex` | Create | Reward choice packet |
| Tests | Create | Unit + integration tests |

## Estimated Scope

| Phase | Files | Complexity |
|-------|-------|------------|
| 1. Store queries | 1 | Low |
| 2. NPC interaction | 3 | Medium |
| 3. Prerequisites | 2 | Low |
| 4. Objective types | 1 | High (48+ types) |
| 5. Rewards | 2 | Medium |
| 6. Testing | 4 | Medium |

## Dependencies

- Existing quest schemas (complete)
- Existing quest context (complete)
- Existing quest packets (partial)
- Inventory system (for rewards)
- XP system (for rewards)
- Reputation system (for rewards)

## Success Criteria

1. Player can talk to any quest-giving NPC and see available quests
2. Player can accept quests with prerequisite validation
3. All 48+ objective types progress correctly
4. Quest turn-in grants all reward types (XP, gold, items, reputation)
5. 5,194 quests accessible across all zones
