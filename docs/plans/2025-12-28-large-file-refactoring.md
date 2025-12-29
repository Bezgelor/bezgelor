# Large File Refactoring Plan

**Date:** 2025-12-28
**Purpose:** Refactor oversized source files to improve maintainability and reduce Claude context usage

---

## Executive Summary

| File | Lines | Functions | Priority | Estimated Effort |
|------|-------|-----------|----------|------------------|
| `store.ex` | 3,593 | 161 | 🔴 High | 8-12 tasks |
| `event_manager.ex` | 1,849 | 89 | 🟡 Medium | 4-6 tasks |
| `instance.ex` | 1,509 | 73 | 🟡 Medium | 4-6 tasks |

---

## 1. BezgelorData.Store Refactoring

### Current State
- **Location:** `apps/bezgelor_data/lib/bezgelor_data/store.ex`
- **Lines:** 3,593
- **Functions:** 161 (98 public, 63 private)
- **Responsibilities:** Everything - ETS management, 65+ data tables, indexes, queries

### Proposed Structure

```
apps/bezgelor_data/lib/bezgelor_data/
├── store.ex                    # Core GenServer, table management (~400 lines)
├── store/
│   ├── core.ex                 # get/list/paginated/count operations (~200 lines)
│   ├── loader.ex               # Data loading orchestration (~300 lines)
│   ├── index.ex                # Index building and lookup (~200 lines)
│   ├── creatures.ex            # Creature data, spawns, affiliations (~400 lines)
│   ├── spells.ex               # Spells, effects, telegraphs (~350 lines)
│   ├── items.ex                # Items, displays, visuals (~400 lines)
│   ├── quests.ex               # Quests, objectives, rewards (~200 lines)
│   ├── zones.ex                # Zones, world locations, bind points (~250 lines)
│   ├── events.ex               # Public events, world bosses, loot (~300 lines)
│   ├── splines.ex              # Splines, patrol paths, entity splines (~400 lines)
│   ├── characters.ex           # Character creation, customization (~300 lines)
│   └── tradeskills.ex          # Tradeskill professions, schematics (~150 lines)
```

### Migration Strategy

1. **Phase 1: Extract Core Operations**
   - Create `BezgelorData.Store.Core` with get/list/paginated/count
   - Delegate from main Store module for backwards compatibility
   - No API changes

2. **Phase 2: Extract Loaders**
   - Create `BezgelorData.Store.Loader` with all `load_*` functions
   - Create `BezgelorData.Store.Index` with index building
   - Called from Store.init/1

3. **Phase 3: Extract Domain Modules**
   - One module per domain (creatures, spells, items, etc.)
   - Each module handles:
     - Domain-specific queries (get_spell_effects, get_creature, etc.)
     - Domain-specific loaders (load_spells_split, etc.)
   - Main Store delegates to domain modules

4. **Phase 4: Update BezgelorData Facade**
   - Update `BezgelorData` module to delegate to new modules
   - Maintain full backwards compatibility

### Function Distribution

| Domain Module | Functions | Key Responsibilities |
|--------------|-----------|---------------------|
| `store/core.ex` | 12 | get, list, list_paginated, count, collect_all_pages |
| `store/loader.ex` | 15 | load_json_raw, load_table_by_zone, load_client_table |
| `store/index.ex` | 6 | build_all_indexes, build_index, lookup_index, fetch_by_ids |
| `store/creatures.ex` | 12 | creatures, spawns, affiliations, loot rules |
| `store/spells.ex` | 14 | spell4_entries, effects, telegraphs, spell_levels |
| `store/items.ex` | 18 | items, displays, visuals, slots, model paths |
| `store/quests.ex` | 8 | quests, objectives, rewards, categories |
| `store/zones.ex` | 10 | zones, world_locations, bind_points |
| `store/events.ex` | 16 | public_events, world_bosses, spawn_points, loot_tables |
| `store/splines.ex` | 18 | splines, nodes, patrol_paths, entity_splines |
| `store/characters.ex` | 12 | character_creations, customizations, visuals |
| `store/tradeskills.ex` | 6 | professions, schematics, talents, nodes |

---

## 2. EventManager Refactoring

### Current State
- **Location:** `apps/bezgelor_world/lib/bezgelor_world/event_manager.ex`
- **Lines:** 1,849
- **Functions:** 89
- **Responsibilities:** Event lifecycle, objectives, world bosses, waves, territory, rewards

### Proposed Structure

```
apps/bezgelor_world/lib/bezgelor_world/
├── event_manager.ex            # Main GenServer, routing (~400 lines)
├── event/
│   ├── lifecycle.ex            # start_event, stop_event, complete_event (~200 lines)
│   ├── objectives.ex           # Objective tracking, updates (~250 lines)
│   ├── participation.ex        # Join, leave, contribution tracking (~200 lines)
│   ├── world_boss.ex           # Boss spawning, damage, phases (~300 lines)
│   ├── waves.ex                # Wave mechanics, enemy tracking (~250 lines)
│   ├── territory.ex            # Territory capture mechanics (~250 lines)
│   └── rewards.ex              # Reward calculation, distribution (~200 lines)
```

### Migration Strategy

1. **Phase 1: Extract Pure Functions**
   - Move reward calculation to `event/rewards.ex`
   - Move objective parsing to `event/objectives.ex`
   - No GenServer changes

2. **Phase 2: Extract Handler Logic**
   - Keep handle_call/handle_cast in main module
   - Extract actual logic to domain modules
   - Pattern: `handle_call({:start_wave, ...}, ...) -> Waves.start(state, ...)`

3. **Phase 3: Simplify Main Module**
   - Main module becomes a thin dispatcher
   - All business logic in sub-modules

---

## 3. World.Instance Refactoring

### Current State
- **Location:** `apps/bezgelor_world/lib/bezgelor_world/world/instance.ex`
- **Lines:** 1,509
- **Functions:** 73
- **Responsibilities:** Entities, creatures, combat, harvest nodes, spawning

### Proposed Structure

```
apps/bezgelor_world/lib/bezgelor_world/world/
├── instance.ex                 # Main GenServer, entity routing (~400 lines)
├── instance/
│   ├── entities.ex             # Entity CRUD, position updates (~250 lines)
│   ├── creatures.ex            # Creature management, combat (~350 lines)
│   ├── harvest_nodes.ex        # Harvest node spawning, gathering (~250 lines)
│   ├── spawning.ex             # Spawn loading, creature generation (~300 lines)
│   └── spatial.ex              # Range queries, idle timeout (~150 lines)
```

### Migration Strategy

1. **Phase 1: Extract Spawn Logic**
   - Move `load_spawns_sync`, `spawn_from_definitions` to `instance/spawning.ex`
   - Move harvest node spawning to `instance/harvest_nodes.ex`

2. **Phase 2: Extract Entity Logic**
   - Move entity CRUD to `instance/entities.ex`
   - Move creature combat to `instance/creatures.ex`

3. **Phase 3: Simplify Main Module**
   - Main module handles GenServer callbacks
   - Delegates to sub-modules for business logic

---

## Task Breakdown

### Epic: Store Refactoring (bzglr-???)

| Task ID | Description | Depends On |
|---------|-------------|------------|
| 1 | Create store/core.ex with get/list/paginated operations | - |
| 2 | Create store/loader.ex with data loading functions | - |
| 3 | Create store/index.ex with index building | - |
| 4 | Create store/creatures.ex with creature data functions | 1, 2 |
| 5 | Create store/spells.ex with spell/telegraph functions | 1, 2 |
| 6 | Create store/items.ex with item/display functions | 1, 2 |
| 7 | Create store/events.ex with event/boss functions | 1, 2, 3 |
| 8 | Create store/splines.ex with spline/patrol functions | 1, 2, 3 |
| 9 | Create store/characters.ex with creation/customization | 1, 2, 3 |
| 10 | Create store/zones.ex and store/quests.ex | 1, 2, 3 |
| 11 | Update Store.ex to delegate to sub-modules | 1-10 |
| 12 | Verify all tests pass, no API changes | 11 |

### Epic: EventManager Refactoring (bzglr-???)

| Task ID | Description | Depends On |
|---------|-------------|------------|
| 1 | Create event/rewards.ex with reward calculation | - |
| 2 | Create event/objectives.ex with objective logic | - |
| 3 | Create event/world_boss.ex with boss mechanics | - |
| 4 | Create event/waves.ex with wave mechanics | - |
| 5 | Create event/territory.ex with capture logic | - |
| 6 | Refactor EventManager to delegate to sub-modules | 1-5 |

### Epic: Instance Refactoring (bzglr-???)

| Task ID | Description | Depends On |
|---------|-------------|------------|
| 1 | Create instance/spawning.ex with spawn logic | - |
| 2 | Create instance/harvest_nodes.ex | - |
| 3 | Create instance/creatures.ex with combat | - |
| 4 | Create instance/entities.ex with CRUD | - |
| 5 | Refactor Instance to delegate to sub-modules | 1-4 |

---

## Backwards Compatibility

All refactoring MUST maintain backwards compatibility:

1. **No API Changes**: All public functions remain callable with same signatures
2. **Delegation Pattern**: Original modules delegate to new sub-modules
3. **Test Coverage**: All existing tests must pass without modification
4. **Gradual Migration**: Can be done incrementally, one domain at a time

Example delegation pattern:
```elixir
# In store.ex
defdelegate get_spell_effects(spell_id), to: BezgelorData.Store.Spells

# In store/spells.ex
def get_spell_effects(spell_id) do
  # Implementation moved here
end
```

---

## Success Criteria

- [ ] No file exceeds 600 lines
- [ ] All existing tests pass
- [ ] No API changes (full backwards compatibility)
- [ ] Each module has single responsibility
- [ ] Clear separation between GenServer callbacks and business logic
