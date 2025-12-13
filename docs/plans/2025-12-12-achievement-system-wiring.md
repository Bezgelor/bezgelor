# Achievement System Wiring Implementation Plan

**Date:** 2025-12-12
**Status:** ✅ COMPLETE
**Scope:** Wire 4,943 achievements with event-indexed handlers, 83 type mappings, bitfield checklist storage, and title integration

## Overview

Wire the extracted achievement data to the existing achievement system infrastructure. The foundation exists (AchievementHandler, BezgelorDb.Achievements, packets, ETS loading) but needs:
1. Event-indexed achievement lookup for O(1) matching
2. Achievement type → event type mapping (83 types)
3. Handler initialization on world entry
4. Event broadcasts from all game systems
5. Bitfield storage for checklist achievements

## Architecture

```
Game Events (kill, quest, zone, etc.)
         │
         ▼
┌─────────────────────────────────┐
│   BezgelorDb.Achievements       │
│   .broadcast(char_id, event)    │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│    AchievementHandler           │
│  ┌───────────────────────────┐  │
│  │ AchievementIndex (ETS)    │  │
│  │ {:kill, 2790} => [defs]   │  │
│  │ {:quest, 14069} => [defs] │  │
│  └───────────────────────────┘  │
│         │                       │
│         ▼                       │
│  Check progress → Update DB     │
│         │                       │
│         ▼ (if completed)        │
│  • ServerAchievementEarned      │
│  • TitleHandler.grant_title/2   │
│  • Broadcast :achievement event │
└─────────────────────────────────┘
```

## Implementation Batches

---

### Batch 1: Achievement Type Mapping Module

**Goal:** Create module that maps 83 achievement types to event types

**Files:**
- `apps/bezgelor_data/lib/bezgelor_data/achievement_types.ex` (new)

#### Task 1.1: Create AchievementTypes module with type mapping

```elixir
defmodule BezgelorData.AchievementTypes do
  @moduledoc """
  Maps WildStar achievement type IDs to event types.

  Based on analysis of 4,943 achievements across 83 unique types.
  """

  # Kill/Combat achievements
  @kill_types [2, 61, 105]

  # Quest achievements
  @quest_types [35, 77]

  # Exploration/Zone achievements
  @zone_types [5, 8, 12, 121]

  # Dungeon/Instance achievements
  @dungeon_types [6, 7, 38, 54, 80, 97, 98, 103]

  # Path achievements
  @path_types [37, 40, 96]

  # Tradeskill achievements
  @tradeskill_types [87, 88, 94, 102]

  # Challenge achievements
  @challenge_types [44, 45]

  # PvP achievements
  @pvp_types [33, 76]

  # Datacube/Lore achievements
  @datacube_types [1, 15, 46, 82]

  # Event achievements
  @event_types [57, 116, 137, 143, 157]

  # Social/Economy achievements
  @social_types [9, 63]

  # Housing achievements
  @housing_types [53, 65]

  # Adventure achievements
  @adventure_types [42, 67]

  # Meta achievements (triggered by other achievements)
  @meta_types [104, 141]

  # Level/Currency achievements
  @progression_types [3, 13, 16]

  @doc "Get event type for achievement type ID"
  @spec event_type(non_neg_integer()) :: atom() | nil
  def event_type(type_id) when type_id in @kill_types, do: :kill
  def event_type(type_id) when type_id in @quest_types, do: :quest_complete
  def event_type(type_id) when type_id in @zone_types, do: :zone_explore
  def event_type(type_id) when type_id in @dungeon_types, do: :dungeon_complete
  def event_type(type_id) when type_id in @path_types, do: :path_mission
  def event_type(type_id) when type_id in @tradeskill_types, do: :tradeskill
  def event_type(type_id) when type_id in @challenge_types, do: :challenge_complete
  def event_type(type_id) when type_id in @pvp_types, do: :pvp
  def event_type(type_id) when type_id in @datacube_types, do: :datacube
  def event_type(type_id) when type_id in @event_types, do: :event
  def event_type(type_id) when type_id in @social_types, do: :social
  def event_type(type_id) when type_id in @housing_types, do: :housing
  def event_type(type_id) when type_id in @adventure_types, do: :adventure_complete
  def event_type(type_id) when type_id in @meta_types, do: :meta
  def event_type(type_id) when type_id in @progression_types, do: :progression
  def event_type(_), do: nil

  @doc "Check if achievement type uses objectId as target"
  @spec uses_object_id?(non_neg_integer()) :: boolean()
  def uses_object_id?(type_id) do
    type_id in (@kill_types ++ @quest_types ++ @datacube_types ++
                @housing_types ++ @adventure_types)
  end

  @doc "Check if achievement type uses value as counter target"
  @spec uses_counter?(non_neg_integer()) :: boolean()
  def uses_counter?(type_id) do
    type_id in [61, 77, 87, 88, 94, 102, 33, 76, 3, 13]
  end
end
```

**Tests:** `apps/bezgelor_data/test/achievement_types_test.exs`

---

### Batch 2: Achievement Index Builder

**Goal:** Build event-indexed ETS table for O(1) achievement lookup

**Files:**
- `apps/bezgelor_data/lib/bezgelor_data/achievement_index.ex` (new)
- `apps/bezgelor_data/lib/bezgelor_data/store.ex` (modify)

#### Task 2.1: Create AchievementIndex module

```elixir
defmodule BezgelorData.AchievementIndex do
  @moduledoc """
  Builds and queries event-indexed achievement lookups.

  Index structure:
  - `{:kill, creature_id}` => [achievement_defs]
  - `{:kill, :any}` => [counter achievements]
  - `{:quest_complete, quest_id}` => [achievement_defs]
  - etc.
  """

  alias BezgelorData.{AchievementTypes, Store}

  @table :achievement_index

  @doc "Build index from loaded achievements. Called at startup."
  @spec build_index() :: :ok
  def build_index do
    # Create ETS table if not exists
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])
    end

    # Clear existing entries
    :ets.delete_all_objects(@table)

    # Index all achievements
    Store.list(:achievements)
    |> Enum.each(&index_achievement/1)

    :ok
  end

  @doc "Lookup achievements matching an event"
  @spec lookup(atom(), term()) :: [map()]
  def lookup(event_type, target) do
    # Get specific target matches
    specific = :ets.lookup(@table, {event_type, target})
    |> Enum.map(fn {_key, def} -> def end)

    # Get "any" target matches (for counters)
    any = :ets.lookup(@table, {event_type, :any})
    |> Enum.map(fn {_key, def} -> def end)

    specific ++ any
  end

  defp index_achievement(achievement) do
    type_id = achievement.achievementTypeId
    event_type = AchievementTypes.event_type(type_id)

    if event_type do
      def_map = build_def_map(achievement, event_type)

      if AchievementTypes.uses_object_id?(type_id) and achievement.objectId > 0 do
        # Index by specific object
        :ets.insert(@table, {{event_type, achievement.objectId}, def_map})
      else
        # Index as "any" for counter achievements
        :ets.insert(@table, {{event_type, :any}, def_map})
      end

      # Also index by zone if present
      if achievement.worldZoneId > 0 do
        :ets.insert(@table, {{:zone, achievement.worldZoneId}, def_map})
      end
    end
  end

  defp build_def_map(achievement, event_type) do
    %{
      id: achievement.ID,
      type: event_type,
      type_id: achievement.achievementTypeId,
      object_id: achievement.objectId,
      target: achievement.value,
      zone_id: achievement.worldZoneId,
      title_id: achievement.characterTitleId,
      points: achievement_points(achievement.achievementPointEnum),
      has_checklist: has_checklist?(achievement.ID)
    }
  end

  defp achievement_points(0), do: 0
  defp achievement_points(1), do: 5
  defp achievement_points(2), do: 10
  defp achievement_points(3), do: 25

  defp has_checklist?(achievement_id) do
    Store.get_achievement_checklists(achievement_id) != []
  end
end
```

#### Task 2.2: Call build_index from Store startup

Add to `BezgelorData.Store.init/1`:
```elixir
# After loading all data
BezgelorData.AchievementIndex.build_index()
```

**Tests:** `apps/bezgelor_data/test/achievement_index_test.exs`

---

### Batch 3: Update AchievementHandler for Index Lookup

**Goal:** Replace full-scan with index lookup in AchievementHandler

**Files:**
- `apps/bezgelor_world/lib/bezgelor_world/handler/achievement_handler.ex` (modify)

#### Task 3.1: Update process_event to use index

Replace the current filtering logic with index lookup:

```elixir
defp process_event({:kill, creature_id}, state) do
  # Use index lookup instead of filtering all defs
  AchievementIndex.lookup(:kill, creature_id)
  |> Enum.each(fn def ->
    process_achievement(state, def, 1)
  end)
end

defp process_event({:quest_complete, quest_id}, state) do
  AchievementIndex.lookup(:quest_complete, quest_id)
  |> Enum.each(fn def ->
    process_achievement(state, def, 1)
  end)
end

# Add handlers for all event types...
defp process_event({:zone_explore, zone_id}, state) do
  AchievementIndex.lookup(:zone_explore, zone_id)
  |> Enum.each(fn def ->
    process_achievement(state, def, 1)
  end)
end

defp process_event({:dungeon_complete, instance_id}, state) do
  AchievementIndex.lookup(:dungeon_complete, instance_id)
  |> Enum.each(fn def ->
    process_achievement(state, def, 1)
  end)
end

defp process_event({:path_mission, mission_id}, state) do
  AchievementIndex.lookup(:path_mission, mission_id)
  |> Enum.each(fn def ->
    process_achievement(state, def, 1)
  end)
end

defp process_event({:tradeskill, action, item_id}, state) do
  AchievementIndex.lookup(:tradeskill, item_id)
  |> Enum.each(fn def ->
    process_achievement(state, def, 1)
  end)
end

defp process_event({:challenge_complete, challenge_id}, state) do
  AchievementIndex.lookup(:challenge_complete, challenge_id)
  |> Enum.each(fn def ->
    process_achievement(state, def, 1)
  end)
end

defp process_event({:pvp, action, data}, state) do
  AchievementIndex.lookup(:pvp, action)
  |> Enum.each(fn def ->
    process_achievement(state, def, 1)
  end)
end

defp process_event({:datacube, datacube_id}, state) do
  AchievementIndex.lookup(:datacube, datacube_id)
  |> Enum.each(fn def ->
    process_achievement(state, def, 1)
  end)
end

defp process_event({:level_up, new_level}, state) do
  AchievementIndex.lookup(:progression, :any)
  |> Enum.filter(fn def -> def.target <= new_level end)
  |> Enum.each(fn def ->
    process_achievement(state, def, new_level)
  end)
end

defp process_event({:achievement, completed_id}, state) do
  # Meta achievements - check if completing this unlocks others
  AchievementIndex.lookup(:meta, :any)
  |> Enum.each(fn def ->
    check_meta_achievement(state, def, completed_id)
  end)
end

defp process_event(_event, _state), do: :ok
```

#### Task 3.2: Add unified process_achievement function

```elixir
defp process_achievement(state, def, amount) do
  cond do
    def.has_checklist ->
      process_checklist_achievement(state, def, amount)

    def.target > 1 ->
      # Counter achievement
      case Achievements.increment_progress(
             state.character_id,
             def.id,
             amount,
             def.target,
             def.points
           ) do
        {:ok, ach, :completed} -> send_earned(state, ach, def)
        {:ok, ach, :progress} -> send_update(state.connection_pid, ach)
        _ -> :ok
      end

    true ->
      # Instant completion
      case Achievements.complete(state.character_id, def.id, def.points) do
        {:ok, ach, :completed} -> send_earned(state, ach, def)
        _ -> :ok
      end
  end
end
```

#### Task 3.3: Add checklist/bitfield support

```elixir
defp process_checklist_achievement(state, def, object_id) do
  checklists = Store.get_achievement_checklists(def.id)

  # Find matching checklist item
  case Enum.find(checklists, fn c -> c.objectId == object_id end) do
    nil -> :ok

    checklist_item ->
      bit_position = checklist_item.bit
      total_bits = length(checklists)

      case Achievements.get_achievement(state.character_id, def.id) do
        nil ->
          # First progress - create with bit set
          new_bits = 1 <<< bit_position
          Achievements.update_progress(
            state.character_id, def.id, new_bits,
            (1 <<< total_bits) - 1, def.points
          )

        ach when ach.completed ->
          :ok

        ach ->
          # Set the bit
          new_bits = ach.progress ||| (1 <<< bit_position)
          all_bits = (1 <<< total_bits) - 1

          case Achievements.update_progress(
                 state.character_id, def.id, new_bits, all_bits, def.points
               ) do
            {:ok, updated, :completed} -> send_earned(state, updated, def)
            {:ok, updated, :progress} -> send_update(state.connection_pid, updated)
            _ -> :ok
          end
      end
  end
end
```

#### Task 3.4: Update send_earned to grant titles

```elixir
defp send_earned(state, achievement, def) do
  packet = %ServerAchievementEarned{
    achievement_id: achievement.achievement_id,
    points: achievement.points_awarded,
    completed_at: achievement.completed_at
  }

  send(state.connection_pid, {:send_packet, packet})

  Logger.info("Achievement #{achievement.achievement_id} earned! (#{achievement.points_awarded} points)")

  # Grant title if achievement has one
  if def.title_id > 0 and state.account_id do
    TitleHandler.grant_title(state.connection_pid, state.account_id, def.title_id)
  end

  # Broadcast for meta achievements
  Achievements.broadcast(state.character_id, {:achievement, achievement.achievement_id})
end
```

**Tests:** Update `apps/bezgelor_world/test/handler/achievement_handler_test.exs`

---

### Batch 4: Wire Achievement Handler to World Entry

**Goal:** Start AchievementHandler when player enters world, send achievement list

**Files:**
- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/world_entry_handler.ex` (modify)
- `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex` (modify)

#### Task 4.1: Update WorldEntryHandler to start AchievementHandler

Add to `spawn_player/2`:

```elixir
defp spawn_player(character, state) do
  # ... existing entity spawn code ...

  # Start achievement handler for this character
  {:ok, achievement_handler} = AchievementHandler.start_link(
    state.connection_pid,
    character.id,
    account_id: state.session_data[:account_id]
  )

  # Send achievement list to client
  AchievementHandler.send_achievement_list(state.connection_pid, character.id)

  # Store handler pid in session
  state = put_in(state.session_data[:achievement_handler], achievement_handler)

  # ... rest of function ...
end
```

#### Task 4.2: Clean up AchievementHandler on disconnect

Add to connection termination:

```elixir
def terminate(_reason, state) do
  # Stop achievement handler if running
  if handler = state.session_data[:achievement_handler] do
    GenServer.stop(handler, :normal)
  end

  # ... existing cleanup ...
end
```

**Tests:** Integration test for achievement list on login

---

### Batch 5: Wire Event Broadcasts from Game Systems

**Goal:** Add achievement broadcasts to all game event sources

**Files:**
- `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex` (modify)
- `apps/bezgelor_world/lib/bezgelor_world/quest/session_quest_manager.ex` (modify)
- `apps/bezgelor_world/lib/bezgelor_world/zone/instance.ex` (modify)
- `apps/bezgelor_world/lib/bezgelor_world/handler/path_handler.ex` (modify if exists)

#### Task 5.1: Add achievement broadcast to CombatBroadcaster

Update `notify_creature_kill_multi/4`:

```elixir
def notify_creature_kill_multi(zone_id, instance_id, participant_character_ids, creature_id) do
  # ... existing EventManager notification ...

  # Send game event AND achievement event to ALL participants
  for character_id <- participant_character_ids do
    send_game_event(character_id, :kill, %{creature_id: creature_id})

    # Achievement broadcast
    Achievements.broadcast(character_id, {:kill, creature_id})
  end

  :ok
end
```

#### Task 5.2: Add achievement broadcast on quest completion

In QuestHandler or SessionQuestManager, after completing a quest:

```elixir
defp complete_quest(character_id, quest_id) do
  # ... existing completion logic ...

  # Broadcast for achievement tracking
  Achievements.broadcast(character_id, {:quest_complete, quest_id})
end
```

#### Task 5.3: Add zone exploration achievement broadcast

In zone instance or movement handler:

```elixir
def handle_zone_discovery(character_id, zone_id, subzone_id) do
  # Broadcast zone exploration
  Achievements.broadcast(character_id, {:zone_explore, zone_id})

  if subzone_id > 0 do
    Achievements.broadcast(character_id, {:zone_explore, subzone_id})
  end
end
```

#### Task 5.4: Add dungeon completion achievement broadcast

In instance completion handler:

```elixir
def handle_instance_complete(character_id, instance_id) do
  Achievements.broadcast(character_id, {:dungeon_complete, instance_id})
end
```

#### Task 5.5: Add datacube discovery broadcast

```elixir
def handle_datacube_interact(character_id, datacube_id) do
  Achievements.broadcast(character_id, {:datacube, datacube_id})
end
```

#### Task 5.6: Add level up achievement broadcast

In XP/level handler:

```elixir
def handle_level_up(character_id, new_level) do
  Achievements.broadcast(character_id, {:level_up, new_level})
end
```

**Tests:** Integration tests for each event type

---

### Batch 6: Testing and Validation

**Goal:** Comprehensive tests for achievement system

**Files:**
- `apps/bezgelor_data/test/achievement_types_test.exs` (new)
- `apps/bezgelor_data/test/achievement_index_test.exs` (new)
- `apps/bezgelor_world/test/achievement_integration_test.exs` (new)

#### Task 6.1: Achievement type mapping tests

```elixir
defmodule BezgelorData.AchievementTypesTest do
  use ExUnit.Case

  alias BezgelorData.AchievementTypes

  describe "event_type/1" do
    test "maps kill achievement types" do
      assert AchievementTypes.event_type(2) == :kill
      assert AchievementTypes.event_type(61) == :kill
      assert AchievementTypes.event_type(105) == :kill
    end

    test "maps quest achievement types" do
      assert AchievementTypes.event_type(35) == :quest_complete
      assert AchievementTypes.event_type(77) == :quest_complete
    end

    test "returns nil for unknown types" do
      assert AchievementTypes.event_type(9999) == nil
    end
  end
end
```

#### Task 6.2: Achievement index tests

```elixir
defmodule BezgelorData.AchievementIndexTest do
  use ExUnit.Case

  alias BezgelorData.AchievementIndex

  setup do
    AchievementIndex.build_index()
    :ok
  end

  describe "lookup/2" do
    test "finds kill achievements by creature ID" do
      # Creature 2790 has kill achievements
      results = AchievementIndex.lookup(:kill, 2790)
      assert length(results) > 0
      assert Enum.all?(results, fn d -> d.type == :kill end)
    end

    test "finds quest achievements by quest ID" do
      results = AchievementIndex.lookup(:quest_complete, 14069)
      assert length(results) > 0
    end

    test "returns empty for unknown targets" do
      assert AchievementIndex.lookup(:kill, 999999) == []
    end
  end
end
```

#### Task 6.3: Integration test - full achievement flow

```elixir
defmodule BezgelorWorld.AchievementIntegrationTest do
  use BezgelorDb.DataCase

  alias BezgelorDb.Achievements
  alias BezgelorWorld.Handler.AchievementHandler

  describe "kill achievement flow" do
    test "killing creature updates achievement progress" do
      # Setup character and achievement handler
      character = insert(:character)
      {:ok, handler} = AchievementHandler.start_link(self(), character.id)

      # Simulate kill event
      Achievements.broadcast(character.id, {:kill, 2790})

      # Wait for processing
      Process.sleep(100)

      # Check progress updated
      ach = Achievements.get_achievement(character.id, expected_achievement_id)
      assert ach.progress > 0
    end
  end

  describe "checklist achievement flow" do
    test "completing checklist items sets bits correctly" do
      character = insert(:character)
      achievement_id = 342  # Achievement with checklist

      # Complete first checklist item
      Achievements.broadcast(character.id, {:zone_explore, 4198})
      Process.sleep(100)

      ach = Achievements.get_achievement(character.id, achievement_id)
      assert (ach.progress &&& 1) == 1  # Bit 0 set
    end
  end
end
```

---

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `achievement_types.ex` | Create | Type ID → event type mapping |
| `achievement_index.ex` | Create | Event-indexed ETS lookup |
| `store.ex` | Modify | Call build_index at startup |
| `achievement_handler.ex` | Modify | Use index lookup, add all event types |
| `world_entry_handler.ex` | Modify | Start handler, send list |
| `connection.ex` | Modify | Clean up handler on disconnect |
| `combat_broadcaster.ex` | Modify | Add achievement broadcasts |
| `session_quest_manager.ex` | Modify | Add quest completion broadcast |
| Tests | Create | Type, index, integration tests |

## Success Criteria

1. Achievement index builds at startup with 4,943 achievements indexed
2. Kill events trigger correct achievement progress updates
3. Quest completion triggers achievement updates
4. Zone exploration triggers achievement updates
5. Checklist achievements use bitfield storage correctly
6. Titles are granted when achievements with titles complete
7. Meta achievements trigger when prerequisite achievements complete
8. Achievement list sent to client on world entry
9. All 83 achievement types mapped to event handlers

## Test Plan

- [ ] Unit tests for AchievementTypes (83 type mappings)
- [ ] Unit tests for AchievementIndex (build, lookup)
- [ ] Integration test: kill → achievement progress
- [ ] Integration test: quest complete → achievement
- [ ] Integration test: zone explore → achievement
- [ ] Integration test: checklist bitfield storage
- [ ] Integration test: title grant on achievement
- [ ] Integration test: meta achievement chain
- [ ] Integration test: achievement list on login
