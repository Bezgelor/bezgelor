# Phase 6 Completion: Core Gameplay

**Status:** ✅ Complete

## Overview

Complete the remaining Phase 6 components from the original roadmap:
- Creature spawning and AI
- Targeting system
- Death and respawn
- Experience and leveling
- Loot drops

## 1. Creature System

### Creature Template

Static data defining creature types:

```elixir
%CreatureTemplate{
  id: 1,
  name: "Training Dummy",
  level: 1,
  max_health: 100,
  faction: :hostile,
  display_info: 1001,
  ai_type: :passive,        # :passive | :aggressive | :defensive
  aggro_range: 10.0,
  leash_range: 40.0,
  respawn_time: 30_000,     # ms
  xp_reward: 50,
  loot_table_id: 1
}
```

### CreatureManager

GenServer that manages creature spawns:
- Spawns creatures from templates at defined locations
- Tracks creature state (alive, dead, combat)
- Handles respawning after death
- Routes AI decisions

## 2. AI State Machine

Simple state machine for creature behavior:

```
States:
  :idle       -> Standing at spawn, not in combat
  :patrol     -> Following patrol path (future)
  :combat     -> Engaged with target
  :evade      -> Returning to spawn (leashed)
  :dead       -> Waiting for respawn

Transitions:
  idle + player_in_range -> combat (if aggressive)
  combat + target_dead -> idle
  combat + target_out_of_leash -> evade
  evade + at_spawn -> idle
  any + health=0 -> dead
  dead + respawn_timer -> idle
```

## 3. Targeting System

### Target State

Each entity can have:
- `target_guid` - Currently targeted entity
- `targeted_by` - List of entities targeting this one (for threat)

### Target Validation

- Range check
- Line of sight (simplified - just distance)
- Faction check (can't target friendly with hostile spells)
- Alive check

### Packets

| Opcode | Name | Direction | Description |
|--------|------|-----------|-------------|
| 0x0500 | ClientSetTarget | C→S | Player targets entity |
| 0x0501 | ServerTargetUpdate | S→C | Target changed |

## 4. Death and Respawn

### Player Death
1. Health reaches 0
2. Set death state flag
3. Send death packet to client
4. Player can respawn at graveyard (simplified: respawn at same location)
5. Restore to full health on respawn

### Creature Death
1. Health reaches 0
2. Generate loot
3. Award XP to killer
4. Start respawn timer
5. Remove from world (or show corpse)
6. After timer, respawn at spawn point

### Packets

| Opcode | Name | Direction | Description |
|--------|------|-----------|-------------|
| 0x0510 | ServerEntityDeath | S→C | Entity died |
| 0x0511 | ClientRespawn | C→S | Player requests respawn |
| 0x0512 | ServerRespawn | S→C | Entity respawned |

## 5. Experience and Leveling

### XP Formula

```elixir
# XP required for next level
def xp_for_level(level) do
  base = 100
  base * level * level
end

# XP from killing creature
def xp_from_kill(player_level, creature_level, base_xp) do
  level_diff = creature_level - player_level

  multiplier = cond do
    level_diff >= 5 -> 1.2      # Much higher level
    level_diff >= 2 -> 1.1      # Higher level
    level_diff <= -5 -> 0.1     # Much lower (gray)
    level_diff <= -3 -> 0.5     # Lower (green)
    true -> 1.0                  # Same level
  end

  trunc(base_xp * multiplier)
end
```

### Level Up
1. Check if XP >= XP needed
2. Increment level
3. Subtract XP needed (overflow carries)
4. Increase max health
5. Send level up packet

### Packets

| Opcode | Name | Direction | Description |
|--------|------|-----------|-------------|
| 0x0520 | ServerXPGain | S→C | XP awarded |
| 0x0521 | ServerLevelUp | S→C | Player leveled up |

## 6. Loot System

### Loot Table

```elixir
%LootTable{
  id: 1,
  entries: [
    %{item_id: 1, chance: 100, min: 1, max: 5},   # Always drops 1-5 gold
    %{item_id: 101, chance: 25, min: 1, max: 1},  # 25% chance for item
  ]
}
```

### Loot Generation
1. On creature death, roll loot table
2. Create loot container (simplified: direct to player inventory later)
3. For now: just award gold/XP directly

### Packets

| Opcode | Name | Direction | Description |
|--------|------|-----------|-------------|
| 0x0530 | ServerLootDrop | S→C | Loot available |

## Implementation Tasks

| Task | Description | Status |
|------|-------------|--------|
| 1 | Creature Template Module (`bezgelor_core/creature_template.ex`) | ✅ Done |
| 2 | Combat Module (`bezgelor_world/handler/combat_handler.ex`) | ✅ Done |
| 3 | Experience Module (`bezgelor_core/experience.ex`) | ✅ Done |
| 4 | Loot Module (`bezgelor_core/loot.ex`) | ✅ Done |
| 5 | AI Module (`bezgelor_core/ai.ex`) | ✅ Done |
| 6 | CreatureManager (`bezgelor_world/creature_manager.ex`) | ✅ Done |
| 7 | Target Packets (`client_set_target.ex`, `server_target_update.ex`) | ✅ Done |
| 8 | Death/Respawn Packets (`server_entity_death.ex`, `client_respawn.ex`, `server_respawn.ex`) | ✅ Done |
| 9 | XP/Level Packets (`server_xp_gain.ex`, `server_level_up.ex`) | ✅ Done |
| 10 | Combat Handler Updates (spell damage, death handling) | ✅ Done |

## Success Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | Creatures spawn in the world | ✅ Done |
| 2 | Player can target creatures | ✅ Done |
| 3 | Spells damage targeted creatures | ✅ Done |
| 4 | Creatures die when health = 0 | ✅ Done |
| 5 | Player gains XP on kill | ✅ Done |
| 6 | Player levels up when XP threshold reached | ✅ Done |
| 7 | Creatures respawn after timer | ✅ Done |
| 8 | Players can respawn after death | ✅ Done |

## Implementation Notes

**Files Implemented:**
- `apps/bezgelor_core/lib/bezgelor_core/creature_template.ex` - Creature definitions
- `apps/bezgelor_core/lib/bezgelor_core/ai.ex` - AI state machine
- `apps/bezgelor_core/lib/bezgelor_core/experience.ex` - XP calculations
- `apps/bezgelor_core/lib/bezgelor_core/loot.ex` - Loot tables
- `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex` - Creature spawning/management
- `apps/bezgelor_world/lib/bezgelor_world/handler/combat_handler.ex` - Combat and respawn
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_set_target.ex`
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_target_update.ex`
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_entity_death.ex`
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/client_respawn.ex`
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_respawn.ex`
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_xp_gain.ex`
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_level_up.ex`
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_loot_drop.ex`
