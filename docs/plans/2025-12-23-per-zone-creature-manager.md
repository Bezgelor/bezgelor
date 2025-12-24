# Per-Zone Creature Manager Architecture

## Problem Statement

The current global `CreatureManager` singleton creates several issues:

1. **Bottleneck**: Single GenServer processes all spawn requests sequentially
2. **Blocking**: Loading 20k spawns for world 51 blocks all other zones
3. **Redundant State**: Creatures tracked in both CreatureManager.creatures AND World.Instance.entities
4. **Poor Locality**: No concept of which creatures belong to which zone
5. **Always Running**: Consumes resources even for zones with no players
6. **AI Processing**: Single tick handler for all creatures limits parallelism

## Proposed Architecture

### Current (Global Managers)
```
Application
├── CreatureManager (singleton) ─────────────────┐
│   ├── creatures: %{guid => creature_state}     │ Redundant!
│   ├── spawn_definitions: [...]                 │
│   └── handles ALL AI ticks                     │
├── HarvestNodeManager (singleton)               │
└── World.Instance (per-world)                   │
    ├── entities: %{guid => entity} ─────────────┘
    ├── creatures: MapSet (guids only)
    └── spatial_grid
```

### Proposed (Per-Zone Lifecycle)
```
Application
└── World.InstanceSupervisor
    └── World.Instance (per-world, dynamic)
        ├── entities: %{guid => entity}
        ├── creature_states: %{guid => creature_state}  # Merged from CreatureManager
        ├── spawn_definitions: [...]
        ├── spatial_grid
        ├── AI tick handling (self-contained)
        └── HarvestNodes (optional child or inline)
```

## Migration Steps

### Phase 1: Consolidate State into World.Instance

1. **Add creature_states to World.Instance state**
   - Move `creatures` map from CreatureManager to World.Instance
   - Each instance only tracks creatures for its world
   - Remove redundant `creatures` MapSet (use Map.keys instead)

2. **Move spawn loading into World.Instance**
   - `handle_continue(:load_spawns)` already exists
   - Load directly into instance state, not via CreatureManager
   - Each instance loads in parallel (natural parallelism)

3. **Move AI tick handling into World.Instance**
   - Each instance registers with TickScheduler
   - Process only its own creatures
   - Natural parallelism across zones

### Phase 2: Deprecate Global CreatureManager

1. **Keep CreatureManager as facade during transition**
   - Route calls to appropriate World.Instance
   - Log deprecation warnings

2. **Update callers to use World.Instance directly**
   - Combat system
   - Spell system
   - Quest system
   - Any code that queries/updates creatures

3. **Remove CreatureManager module**

### Phase 3: Optimize Per-Zone Processing

1. **Lazy zone activation**
   - Zone instances start when first player enters
   - Spawns load on-demand
   - Zone instances stop after timeout with no players

2. **Per-zone AI batching**
   - Each zone can tune its own tick rate
   - Busy zones (many players) tick faster
   - Empty zones don't tick at all

## API Changes

### Before (Global)
```elixir
# Spawn loading
CreatureManager.load_zone_spawns(world_id)

# Get creature
CreatureManager.get_creature(guid)

# Damage creature
CreatureManager.damage_creature(guid, damage, attacker_guid)

# Get nearby creatures
CreatureManager.get_creatures_in_range(position, radius)
```

### After (Per-Zone)
```elixir
# Spawn loading (automatic on instance start)
# No explicit call needed - happens in handle_continue

# Get creature (need world context)
World.Instance.get_creature({world_id, instance_id}, guid)

# Damage creature
World.Instance.damage_creature({world_id, instance_id}, guid, damage, attacker_guid)

# Get nearby creatures (already have world context from player session)
World.Instance.get_creatures_in_range({world_id, instance_id}, position, radius)
```

## Key Files to Modify

| File | Changes |
|------|---------|
| `world/instance.ex` | Add creature_states, AI tick handling, spawn loading |
| `creature_manager.ex` | Deprecate, then remove |
| `combat_broadcaster.ex` | Update to use World.Instance |
| `spell_manager.ex` | Update creature queries |
| `protocol/handler/*` | Update any creature interactions |
| `zone/manager.ex` | Simplify - no longer coordinates spawn loading |

## Data Flow: Player Attacks Creature

### Current
```
Player -> CombatHandler -> CreatureManager.damage_creature(guid, ...)
                              └── Updates CreatureManager.creatures
                              └── Updates World.Instance.entities (via cast)
```

### Proposed
```
Player -> CombatHandler -> World.Instance.damage_creature(world_key, guid, ...)
                              └── Updates local creature_states
                              └── Updates local entities
                              └── Broadcasts to nearby players
```

## Benefits Summary

| Aspect | Current | Proposed |
|--------|---------|----------|
| Spawn Loading | Sequential (blocked) | Parallel (per-zone) |
| AI Processing | Single thread | Per-zone parallelism |
| Memory | Always loaded | Lazy per-zone |
| State Location | Duplicated | Single source |
| Zone Lifecycle | Independent | Tied to instance |
| Code Complexity | Global coordination | Local encapsulation |

## Risks and Mitigations

1. **Cross-zone creature queries**
   - Risk: Some systems might query creatures across zones
   - Mitigation: Audit callers, most already have world context

2. **Migration complexity**
   - Risk: Many files to update
   - Mitigation: Keep CreatureManager facade during transition

3. **Testing**
   - Risk: Tests assume global CreatureManager
   - Mitigation: Update test helpers to spawn World.Instance

## Estimated Effort

- Phase 1: 2-3 sessions (consolidate state)
- Phase 2: 1-2 sessions (deprecate global manager)
- Phase 3: 1 session (optimizations)

## Related Considerations

- **HarvestNodeManager**: ✅ MERGED - Same pattern as CreatureManager, now per-zone in World.Instance
- **Creature.ZoneManager**: Already exists but underutilized - evaluate if needed
- **TickScheduler**: Currently broadcasts to all listeners; per-zone instances would each register
- **CorpseManager**: Could be merged into World.Instance (future work)
- **EventManager**: Could be merged into World.Instance (future work)

## Implementation Status

### Phase 1: Consolidate State ✅
- Creature states merged into World.Instance
- Spawn loading moved to per-zone

### Phase 2: Deprecate Global Managers ✅
- CreatureManager deprecated (facade routes to World.Instance)
- HarvestNodeManager deprecated (facade routes to World.Instance)

### Phase 3: Lazy Zone Activation ✅
- Lazy loading option for World.Instance
- Spawns deferred until first player enters
- Idle timeout stops instance after 5 minutes with no players
- Skip AI processing for empty zones

### Additional: HarvestNodeManager Migration ✅
- Harvest node state added to World.Instance
- Spawn loading via Store.get_resource_spawns
- Gather/deplete/respawn logic moved to World.Instance
- Deprecated facade for backwards compatibility

## Decision

Approved for implementation: [X]
Date: 2025-12-23
Notes: All phases complete. CreatureManager and HarvestNodeManager merged into World.Instance.
