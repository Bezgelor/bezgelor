# Phase 10: Dungeons & Instances - Implementation Plan

**Created:** 2025-12-11
**Status:** Planning Complete

## Overview

Phase 10 implements the complete instanced content system for Bezgelor, covering dungeons, adventures, raids, and expeditions with full group finder integration, boss encounter scripting, lockout management, and loot distribution.

---

## Design Decisions Summary

| Aspect | Decision | Configurable |
|--------|----------|--------------|
| Instance types | Full spectrum (dungeons, adventures, raids, expeditions) | N/A |
| Process architecture | Hybrid (Instance GenServer + boss encounter processes) | N/A |
| Group finder matching | Tiered (FIFO normal, smart veteran/raids) | Yes |
| Boss scripting | Hybrid DSL with Elixir macros | N/A |
| Lockout system | Flexible hybrid tracking all data | Yes |
| Loot distribution | Full suite with smart defaults | Yes |
| Difficulty modes | Normal/Veteran/Challenge + Mythic+ keystones | Yes |
| Instance lifecycle | Tiered by content type | Yes |
| Instance entry | Per-content teleport rules | Yes |
| Role validation | Gear-scored with class/spec checks | Yes |
| Boss mechanics | Full toolkit DSL primitives | N/A |
| Data storage | Hybrid (ETS static, DB player, memory active) | N/A |

---

## Group Finder Matching Tiers

The group finder uses different matching algorithms based on content difficulty:

### Tier 1: Simple FIFO (Normal Dungeons, Adventures, Expeditions)
- First-come-first-served queue processing
- Only validates role requirements (1 Tank, 1 Healer, 3 DPS for 5-player)
- Prioritizes queue time over group optimization
- No gear score requirements (or very minimal)

### Tier 2: Smart Matching (Veteran Dungeons, Veteran Adventures)
- Considers gear score for role (tank needs defense, healer needs support power)
- Tracks completion rate - avoids matching chronic leavers together
- Balances average group gear score (no extreme disparities)
- Optional: considers player ratings/feedback from previous runs

### Tier 3: Advanced Matching (Raids, Mythic+ High Keys)
- All Tier 2 features plus:
- Role composition optimization (raid buffs, class synergy)
- Experience weighting (prior boss kills count)
- Voice chat preference matching
- Guild/friend priority grouping
- Learning run vs speed run preference matching

### Configuration Options

All group finder behavior is fully configurable:

```elixir
# config/runtime.exs
config :bezgelor_world, :group_finder,
  # Enable/disable group finder entirely
  enabled: true,

  # Matching tier per content type (can reassign any content to any tier)
  matching_tiers: %{
    expedition: :simple,
    adventure_normal: :simple,
    dungeon_normal: :simple,
    adventure_veteran: :smart,
    dungeon_veteran: :smart,
    raid_normal: :advanced,
    raid_veteran: :advanced,
    mythic_plus: :advanced
  },

  # Simple (FIFO) tier settings
  simple_matching: %{
    enabled: true,
    max_queue_time_seconds: 1800,  # Force pop after 30 min even if suboptimal
    allow_undergeared: true         # Ignore gear score in this tier
  },

  # Smart matching weights (must sum to 1.0)
  smart_matching: %{
    enabled: true,
    gear_score_weight: 0.3,
    completion_rate_weight: 0.2,
    queue_time_weight: 0.5,
    # Acceptable variance
    gear_score_variance: 20,        # Max gear score spread in group
    completion_rate_minimum: 0.5    # Exclude <50% completion rate players
  },

  # Advanced matching settings
  advanced_matching: %{
    enabled: true,
    include_smart_factors: true,    # Inherit smart matching factors
    class_synergy_weight: 0.2,
    experience_weight: 0.3,
    preference_matching: true,      # Match voice/learning/speed preferences
    guild_priority_bonus: 0.1       # Bonus for grouping guildmates
  },

  # Global settings
  role_requirements: %{
    party_5: %{tank: 1, healer: 1, dps: 3},
    raid_20: %{tank: 2, healer: 4, dps: 14},
    raid_40: %{tank: 4, healer: 8, dps: 28}
  },

  # Leaver penalty
  leaver_penalty_enabled: true,
  leaver_penalty_minutes: 30,
  leaver_penalty_stacking: true,
  leaver_penalty_max_minutes: 240,

  # Gear score requirements (0 = disabled)
  min_gear_score: %{
    dungeon_normal: 0,
    dungeon_veteran: 50,
    raid_normal: 80,
    raid_veteran: 100
  },

  # Queue behavior
  queue_pop_timeout_seconds: 60,    # Time to accept pop
  backfill_enabled: true,           # Allow joining in-progress instances
  backfill_max_bosses_dead: 2,      # Don't backfill if >2 bosses dead
  cross_realm_enabled: false        # Future: cross-realm matching
```

---

## Instance Types

### Expeditions (1-5 players, scalable)
- **Examples:** Infestation, Fragment Zero, Space Madness
- **Scaling:** Health/damage scales with group size
- **Difficulty:** Normal only (Mythic+ adds scaling difficulty)
- **Lockout:** Soft lockout (diminishing returns after daily cap)
- **Entry:** Queue from anywhere
- **Lifecycle:** Aggressive cleanup (immediate when empty)

### Adventures (5 players)
- **Examples:** Hycrest Insurrection, Malgrave Trail, War of the Wilds
- **Scaling:** Fixed 5-player
- **Difficulty:** Normal and Veteran modes
- **Lockout:** Daily (normal), Weekly (veteran)
- **Entry:** Queue from anywhere
- **Lifecycle:** Grace period (5 min disconnect, 15 min completion)
- **Special:** Branching paths, player choices affect outcome

### Dungeons (5 players)
- **Examples:** Stormtalon's Lair, Kel Voreth, Sanctuary of the Swordmaiden
- **Scaling:** Fixed 5-player
- **Difficulty:** Normal, Veteran, Challenge (medals)
- **Lockout:** Encounter lockout (boss kills tracked, can help others)
- **Entry:** Queue from anywhere (LFG), physical entrance (premade default)
- **Lifecycle:** Grace period

### Raids (20/40 players)
- **Examples:** Genetic Archives (20), Datascape (40)
- **Scaling:** Fixed size
- **Difficulty:** Normal and Veteran
- **Lockout:** Instance lockout (tied to specific instance ID)
- **Entry:** Physical entrance or summon required (default)
- **Lifecycle:** Persistent until weekly reset

---

## Mythic+ Keystone System

In addition to the standard WildStar difficulty modes, Phase 10 adds a Mythic+ style progression system:

### Keystone Mechanics
- Players earn keystones from completing content
- Keystones have a level (1-30+) and target a specific dungeon
- Higher levels increase enemy health/damage exponentially
- Time limit for completion (based on dungeon)
- Depleting a key (failing timer) reduces key level by 1

### Affixes (rotate weekly)
| Level | Affix Type | Examples |
|-------|------------|----------|
| 2+ | Minor | Fortified (more health), Tyrannical (boss power) |
| 5+ | Major | Bolstering (enemies buff on death), Sanguine (healing pools) |
| 10+ | Seasonal | Primal (elemental effects), Encrypted (cloaked enemies) |

### Rewards
- Gear scales with key level
- Weekly chest based on highest completed key
- Achievements and titles for high key completions
- Leaderboards per dungeon

### Configuration

```elixir
config :bezgelor_world, :mythic_plus,
  enabled: true,
  max_key_level: 30,
  scaling_per_level: 0.10,  # 10% health/damage per level
  time_limit_base_seconds: %{
    stormtalon: 1800,
    kel_voreth: 2100,
    swordmaiden: 2400
  },
  affix_rotation_weekly: true,
  affixes: %{
    minor: [:fortified, :tyrannical],
    major: [:bolstering, :sanguine, :raging, :bursting],
    seasonal: [:primal, :encrypted, :shrouded]
  }
```

---

## Boss Encounter DSL

The boss scripting DSL provides a declarative way to define encounters:

### DSL Example

```elixir
defmodule Bezgelor.Encounters.Stormtalon do
  use BezgelorWorld.Encounter.DSL

  encounter :stormtalon do
    name "Stormtalon"
    creature_template 15001
    instance :stormtalon_lair

    # Interrupt armor - must break before CC
    interrupt_armor 2

    phase :ground, default: true do
      # Phase triggers
      transition_to :air, at_health: 70
      transition_to :air, at_health: 40

      # Abilities
      ability :lightning_strike do
        cooldown 8_000
        target :random_player
        telegraph :circle, radius: 8.0
        damage 5000, type: :magic
        cast_time 2_000
      end

      ability :static_charge do
        cooldown 15_000
        target :highest_threat
        telegraph :cone, angle: 60, length: 15.0
        damage 8000, type: :magic
        debuff :shocked, duration: 5_000, stacks: true
        interrupt_required true
      end

      ability :cleave do
        cooldown 5_000
        target :highest_threat
        telegraph :cone, angle: 120, length: 8.0
        damage 6000, type: :physical
      end
    end

    phase :air do
      duration 30_000  # Auto-return to ground after 30s
      transition_to :ground, on: :timer

      on_enter do
        move_to {100.0, 50.0, 25.0}
        announce "Stormtalon takes to the skies!"
        spawn_adds :static_wisps, count: 4, at: :around_room
      end

      ability :eye_of_the_storm do
        cooldown 10_000
        target :room_center
        telegraph :circle, radius: 25.0
        safe_zone :circle, radius: 8.0, at: :room_center
        damage 15000, type: :magic
        cast_time 4_000
      end

      on_exit do
        announce "Stormtalon crashes down!"
        despawn_adds :static_wisps
      end
    end

    phase :enrage do
      trigger at_health: 20

      on_enter do
        buff :enraged, duration: :permanent
        announce "Stormtalon enters a frenzy!"
      end

      # Inherits all :ground abilities with faster cooldowns
      inherit :ground, cooldown_reduction: 0.5
    end

    # Enrage timer
    enrage_timer 480_000 do  # 8 minutes
      wipe_raid damage: 999999
    end

    # Loot table
    loot_table 15001

    # Achievements
    on_kill do
      grant_achievement :stormtalon_slayer

      # Conditional achievements
      if condition(:no_deaths) do
        grant_achievement :stormtalon_flawless
      end

      if condition(:under_time, seconds: 300) do
        grant_achievement :stormtalon_speedkill
      end
    end
  end
end
```

### DSL Primitives - Full Toolkit

#### Phase Management
- `phase/2` - Define a phase with abilities and triggers
- `transition_to/2` - Phase transition rules (health, timer, event)
- `on_enter/1` - Actions when entering phase
- `on_exit/1` - Actions when leaving phase
- `inherit/2` - Inherit abilities from another phase

#### Target Selection
- `:highest_threat` - Tank (usually)
- `:lowest_threat` - Often healers
- `:random_player` - Any player
- `:random_dps` - Random DPS role
- `:furthest_player` - Range check
- `:closest_player` - Melee range
- `:lowest_health` - Injured players
- `:marked_player` - Player with specific debuff

#### Telegraphs
- `:circle` - Circular AoE (radius)
- `:cone` - Frontal cone (angle, length)
- `:rectangle` - Rectangular AoE (width, length)
- `:ring` - Donut shape (inner_radius, outer_radius)
- `:line` - Linear AoE (width, length)
- `:cross` - Plus-shaped AoE

#### Add Spawns
- `spawn_adds/2` - Spawn creatures
- `despawn_adds/1` - Remove spawned adds
- Spawn locations: `:at_boss`, `:around_room`, `:on_players`, `:at_position`

#### Interrupt Armor
- `interrupt_armor/1` - Set break threshold
- `interrupt_required/1` - Ability must be interrupted

#### Movement
- `move_to/1` - Boss moves to position
- `charge/1` - Charge at target
- `leap/1` - Leap to location
- `teleport/1` - Instant reposition
- `push_players/2` - Knockback
- `pull_players/2` - Grip to position

#### Environmental
- `spawn_hazard/2` - Create damaging zone
- `despawn_hazard/1` - Remove hazard
- `modify_terrain/2` - Platform changes
- `spawn_object/2` - Interactive objects

#### Coordination Mechanics
- `spread/2` - Players must spread apart
- `stack/2` - Players must group up
- `pair/2` - Match players together
- `soak/2` - Requires X players in area

---

## Lockout System

### Tracking Model

```elixir
# All lockout data tracked in database
%InstanceLockout{
  character_id: integer,
  instance_type: :dungeon | :adventure | :raid | :expedition,
  instance_definition_id: integer,
  difficulty: :normal | :veteran | :challenge | :mythic_plus,

  # Instance lockout (raids)
  instance_guid: binary | nil,  # Specific instance ID

  # Encounter lockout (dungeons)
  boss_kills: MapSet.t(),  # Set of killed boss IDs

  # Loot lockout
  loot_received_at: DateTime.t() | nil,
  loot_eligible: boolean,

  # Soft lockout (expeditions)
  completion_count: integer,
  diminishing_returns_factor: float,

  # Reset tracking
  created_at: DateTime.t(),
  expires_at: DateTime.t(),
  extended: boolean  # Player chose to extend
}
```

### Lockout Rules by Content

```elixir
config :bezgelor_world, :lockouts,
  # Reset schedules
  daily_reset_hour: 10,  # 10 AM server time
  weekly_reset_day: :tuesday,
  weekly_reset_hour: 10,

  rules: %{
    expedition: %{
      type: :soft,
      daily_cap: 10,
      diminishing_start: 5,
      diminishing_factor: 0.8  # 80% rewards per run after cap
    },
    adventure_normal: %{
      type: :loot,
      reset: :daily
    },
    adventure_veteran: %{
      type: :encounter,
      reset: :weekly
    },
    dungeon_normal: %{
      type: :none  # No lockout
    },
    dungeon_veteran: %{
      type: :encounter,
      reset: :weekly
    },
    dungeon_challenge: %{
      type: :loot,
      reset: :daily  # Can attempt for medals daily
    },
    raid_normal: %{
      type: :instance,
      reset: :weekly,
      allow_extend: true
    },
    raid_veteran: %{
      type: :instance,
      reset: :weekly,
      allow_extend: true
    },
    mythic_plus: %{
      type: :none  # No lockout, key system handles progression
    }
  }
```

---

## Loot Distribution

### Available Systems

| System | Description | Default For |
|--------|-------------|-------------|
| **Personal** | Each player rolls independently, gets own drops | LFG queues |
| **Need/Greed** | Players choose need/greed/pass, highest roll wins | Premade groups |
| **Round Robin** | Items distributed in rotation | Fast clears |
| **Master Loot** | Leader assigns all items | Organized raids |
| **Group Loot** | Threshold-based (rarity determines system) | Hybrid |

### Smart Defaults

```elixir
config :bezgelor_world, :loot,
  # Default system by content/formation
  defaults: %{
    lfg_queue: :personal,
    premade_group: :need_greed,
    guild_group: :need_greed,
    raid_lfg: :personal,
    raid_premade: :need_greed,
    raid_guild: :master_loot
  },

  # Can group leader override?
  allow_leader_override: true,

  # Need/Greed settings
  need_greed: %{
    need_requires_usable: true,  # Can only need items your class can use
    greed_timeout_seconds: 60,
    auto_pass_on_timeout: true
  },

  # Group loot thresholds
  group_loot: %{
    round_robin_below: :good,      # Green and below
    need_greed_at: :excellent,     # Blue
    master_loot_at: :superb        # Purple and above
  },

  # Roll range
  roll_range: {1, 100},

  # Loot trading window (trade drops to eligible groupmates)
  trade_window_minutes: 120
```

---

## Instance Lifecycle

### Lifecycle States

```
┌─────────────┐
│  CREATING   │ ──── Instance being initialized
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   WAITING   │ ──── Ready, waiting for players
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   ACTIVE    │ ──── Players inside, combat active
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ COMPLETING  │ ──── Final boss dead, loot window
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  CLEANUP    │ ──── Archiving state, terminating
└─────────────┘
```

### Tiered Configuration

```elixir
config :bezgelor_world, :instance_lifecycle,
  expedition: %{
    creation_timeout_ms: 10_000,
    empty_instance_ttl_ms: 0,           # Immediate cleanup
    disconnect_grace_ms: 60_000,         # 1 min to reconnect
    completion_window_ms: 60_000,        # 1 min loot window
    max_idle_time_ms: 300_000           # 5 min AFK kick
  },

  dungeon: %{
    creation_timeout_ms: 30_000,
    empty_instance_ttl_ms: 300_000,      # 5 min grace
    disconnect_grace_ms: 300_000,        # 5 min to reconnect
    completion_window_ms: 900_000,       # 15 min loot window
    max_idle_time_ms: 600_000           # 10 min AFK kick
  },

  adventure: %{
    creation_timeout_ms: 30_000,
    empty_instance_ttl_ms: 300_000,
    disconnect_grace_ms: 300_000,
    completion_window_ms: 900_000,
    max_idle_time_ms: 600_000
  },

  raid: %{
    creation_timeout_ms: 60_000,
    empty_instance_ttl_ms: :persistent,  # Until reset
    disconnect_grace_ms: 600_000,        # 10 min to reconnect
    completion_window_ms: 1800_000,      # 30 min loot window
    max_idle_time_ms: 900_000           # 15 min AFK kick
  }
```

---

## Instance Entry Configuration

```elixir
config :bezgelor_world, :instance_entry,
  # Entry method per content type
  methods: %{
    expedition: [:queue_anywhere],
    adventure_normal: [:queue_anywhere],
    adventure_veteran: [:queue_anywhere, :physical_entrance],
    dungeon_normal: [:queue_anywhere],
    dungeon_veteran: [:queue_anywhere, :physical_entrance],
    dungeon_challenge: [:physical_entrance],
    raid_normal: [:physical_entrance, :summon],
    raid_veteran: [:physical_entrance, :summon],
    mythic_plus: [:physical_entrance, :keystone_holder]
  },

  # Default for premade groups (LFG always uses queue teleport)
  premade_default: %{
    expedition: :queue_anywhere,
    adventure: :queue_anywhere,
    dungeon: :physical_entrance,
    raid: :physical_entrance
  },

  # Summoning settings
  summon: %{
    required_at_entrance: 2,  # 2 players at stone to summon
    summon_cast_time_ms: 10_000,
    summon_range_from_entrance: 50.0
  },

  # Return teleport (after completion or leaving)
  return_to: :last_position,  # or :hearthstone, :capital_city
  return_delay_ms: 10_000
```

---

## Role Validation

```elixir
config :bezgelor_world, :role_validation,
  enabled: true,

  # Which validations to perform
  checks: %{
    class_can_fill: true,      # Class must support role
    spec_matches: true,        # Active spec/stance matches role
    gear_score_minimum: true   # Meet gear requirements
  },

  # Class-to-role mapping
  class_roles: %{
    warrior: [:tank, :dps],
    engineer: [:tank, :dps],
    stalker: [:tank, :dps],
    medic: [:healer, :dps],
    esper: [:healer, :dps],
    spellslinger: [:healer, :dps]
  },

  # Gear score requirements per role per content
  gear_requirements: %{
    dungeon_normal: %{tank: 0, healer: 0, dps: 0},
    dungeon_veteran: %{tank: 50, healer: 45, dps: 40},
    adventure_veteran: %{tank: 50, healer: 45, dps: 40},
    raid_normal: %{tank: 80, healer: 75, dps: 70},
    raid_veteran: %{tank: 100, healer: 95, dps: 90}
  },

  # What happens on validation failure
  on_failure: :prevent_queue,  # or :warn_only

  # Allow override for premade groups
  premade_skip_validation: false
```

---

## Database Schemas

### Static Data (ETS)

```
priv/data/
├── instances.json           # Instance definitions
├── instance_bosses.json     # Boss templates per instance
├── mythic_affixes.json      # Mythic+ affix definitions
└── loot_tables_instance.json # Instance-specific loot
```

### Database Schemas (Ecto)

| Schema | Purpose |
|--------|---------|
| `instance_lockout` | Character lockout state |
| `instance_completion` | Historical completion records |
| `group_finder_queue` | Active queue entries |
| `group_finder_group` | Formed groups awaiting entry |
| `mythic_keystone` | Player keystone inventory |
| `mythic_run` | Completed mythic+ runs (leaderboard) |
| `loot_history` | Loot distribution audit trail |
| `instance_save` | Raid save states (boss kills, trash) |

### In-Memory (GenServer State)

- Active instance processes
- Boss encounter states
- Real-time player positions in instances
- Combat logs (recent only)

---

## Implementation Tasks

### Task 1: Database Migration
Create migration for all instance-related tables.

### Task 2: Instance Schemas
- `InstanceLockout` - Lockout tracking
- `InstanceCompletion` - Completion history
- `InstanceSave` - Raid save state

### Task 3: Group Finder Schemas
- `GroupFinderQueue` - Queue entries
- `GroupFinderGroup` - Formed groups

### Task 4: Mythic+ Schemas
- `MythicKeystone` - Keystone inventory
- `MythicRun` - Run history/leaderboard

### Task 5: Loot Schemas
- `LootHistory` - Distribution audit

### Task 6: Instances Context
Core context module for instance management.

### Task 7: GroupFinder Context
Queue management, matching algorithms.

### Task 8: Lockouts Context
Lockout checking, creation, reset logic.

### Task 9: Static Data Files
JSON definitions for instances, bosses, affixes.

### Task 10: ETS Integration
Load instance definitions into ETS store.

### Task 11: Instance Server Packets
- `ServerInstanceInfo` - Instance details
- `ServerInstanceList` - Available instances
- `ServerGroupFormed` - Group ready notification
- `ServerQueueUpdate` - Queue position/ETA
- `ServerEncounterStart` - Boss pull notification
- `ServerEncounterEnd` - Boss kill/wipe
- `ServerLootDrop` - Loot distribution
- `ServerLootRoll` - Need/greed UI

### Task 12: Instance Client Packets
- `ClientQueueJoin` - Join queue
- `ClientQueueLeave` - Leave queue
- `ClientQueueReady` - Accept pop
- `ClientEnterInstance` - Teleport in
- `ClientLeaveInstance` - Leave instance
- `ClientLootRoll` - Need/greed/pass
- `ClientResetInstance` - Reset (leader)

### Task 13: Boss DSL Module
Implement the encounter DSL macros.

### Task 14: Boss DSL Primitives
Implement all mechanic primitives (telegraphs, spawns, etc.).

### Task 15: Boss Encounter GenServer
Runtime boss encounter process.

### Task 16: Instance GenServer
Per-instance state management.

### Task 17: Instance Supervisor
DynamicSupervisor for instance processes.

### Task 18: Group Finder GenServer
Queue processing, match making.

### Task 19: Group Finder - Simple FIFO
Implement tier 1 matching.

### Task 20: Group Finder - Smart Matching
Implement tier 2 matching.

### Task 21: Group Finder - Advanced Matching
Implement tier 3 matching.

### Task 22: Lockout Manager
Lockout checking, reset scheduling.

### Task 23: Loot Manager
Loot distribution system.

### Task 24: Loot - Personal
Personal loot implementation.

### Task 25: Loot - Need/Greed
Need/greed rolling.

### Task 26: Loot - Master Loot
Leader assignment.

### Task 27: Mythic+ Manager
Keystone, affixes, scoring.

### Task 28: Instance Handler
Packet handling for instance operations.

### Task 29: Group Finder Handler
Packet handling for queue operations.

### Task 30: Sample Encounters
Implement 2-3 example boss encounters with DSL.

### Task 31: Instance Entry/Exit
Teleportation, summoning stone.

### Task 32: Role Validation
Class/spec/gear validation.

### Task 33: Configuration Module
Consolidate all configurable options.

### Task 34: Tests - Schemas
Schema validation tests.

### Task 35: Tests - DSL
Boss DSL compilation tests.

### Task 36: Tests - Group Finder
Matching algorithm tests.

### Task 37: Tests - Lockouts
Lockout logic tests.

### Task 38: Tests - Loot
Loot distribution tests.

### Task 39: Update STATUS.md
Document Phase 10 completion.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        BezgelorWorld                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │  GroupFinder     │    │  LockoutManager  │                   │
│  │  GenServer       │    │  GenServer       │                   │
│  │                  │    │                  │                   │
│  │  - Queue state   │    │  - Reset timers  │                   │
│  │  - Matching      │    │  - Lock checks   │                   │
│  └────────┬─────────┘    └──────────────────┘                   │
│           │                                                      │
│           │ forms group                                          │
│           ▼                                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              InstanceSupervisor (DynamicSupervisor)       │   │
│  │                                                           │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │   │
│  │   │  Instance   │  │  Instance   │  │  Instance   │      │   │
│  │   │  GenServer  │  │  GenServer  │  │  GenServer  │      │   │
│  │   │             │  │             │  │             │      │   │
│  │   │ Dungeon #1  │  │ Raid #42    │  │ Exped #99   │      │   │
│  │   └──────┬──────┘  └──────┬──────┘  └─────────────┘      │   │
│  │          │                │                               │   │
│  │          │                │                               │   │
│  │   ┌──────▼──────┐  ┌──────▼──────┐                       │   │
│  │   │ BossProcess │  │ BossProcess │  (spawned per boss)   │   │
│  │   │ Stormtalon  │  │ Kuralak     │                       │   │
│  │   └─────────────┘  └─────────────┘                       │   │
│  │                                                           │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │  MythicManager   │    │  LootManager     │                   │
│  │  GenServer       │    │  GenServer       │                   │
│  │                  │    │                  │                   │
│  │  - Keystones     │    │  - Distribution  │                   │
│  │  - Affixes       │    │  - Roll tracking │                   │
│  │  - Leaderboard   │    │  - Trade window  │                   │
│  └──────────────────┘    └──────────────────┘                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
apps/bezgelor_db/
├── lib/bezgelor_db/
│   ├── instances.ex                    # Instances context
│   ├── group_finder.ex                 # GroupFinder context
│   ├── lockouts.ex                     # Lockouts context
│   └── schema/
│       ├── instance_lockout.ex
│       ├── instance_completion.ex
│       ├── instance_save.ex
│       ├── group_finder_queue.ex
│       ├── group_finder_group.ex
│       ├── mythic_keystone.ex
│       ├── mythic_run.ex
│       └── loot_history.ex
└── priv/repo/migrations/
    └── 2025XXXX_create_instance_tables.exs

apps/bezgelor_data/priv/data/
├── instances.json
├── instance_bosses.json
├── mythic_affixes.json
└── loot_tables_instance.json

apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/
├── client_queue_join.ex
├── client_queue_leave.ex
├── client_queue_ready.ex
├── client_enter_instance.ex
├── client_leave_instance.ex
├── client_loot_roll.ex
├── client_reset_instance.ex
├── server_instance_info.ex
├── server_instance_list.ex
├── server_group_formed.ex
├── server_queue_update.ex
├── server_encounter_start.ex
├── server_encounter_end.ex
├── server_loot_drop_instance.ex
└── server_loot_roll.ex

apps/bezgelor_world/lib/bezgelor_world/
├── instance/
│   ├── instance.ex                     # Instance GenServer
│   ├── instance_supervisor.ex          # DynamicSupervisor
│   └── instance_registry.ex            # Registry helpers
├── encounter/
│   ├── dsl.ex                          # Boss DSL macros
│   ├── primitives/
│   │   ├── phase.ex
│   │   ├── telegraph.ex
│   │   ├── target.ex
│   │   ├── spawn.ex
│   │   ├── movement.ex
│   │   ├── interrupt.ex
│   │   ├── environmental.ex
│   │   └── coordination.ex
│   ├── boss_process.ex                 # Boss encounter GenServer
│   └── encounters/                     # Concrete boss implementations
│       ├── stormtalon.ex
│       ├── kel_voreth_overlord.ex
│       └── ...
├── group_finder/
│   ├── group_finder.ex                 # Main GenServer
│   ├── matcher_simple.ex               # Tier 1 FIFO
│   ├── matcher_smart.ex                # Tier 2
│   └── matcher_advanced.ex             # Tier 3
├── loot/
│   ├── loot_manager.ex                 # Loot distribution
│   ├── personal_loot.ex
│   ├── need_greed.ex
│   └── master_loot.ex
├── mythic/
│   ├── mythic_manager.ex
│   ├── keystone.ex
│   └── affixes.ex
├── lockout_manager.ex
└── handler/
    ├── instance_handler.ex
    └── group_finder_handler.ex
```

---

## Success Criteria

1. **Group Finder** - Players can queue, get matched, and teleport into instances
2. **Instance Lifecycle** - Instances create, run, and cleanup properly per content type
3. **Boss Encounters** - At least 3 bosses scripted with DSL, all mechanics working
4. **Lockouts** - Proper lockout enforcement per content type, weekly resets work
5. **Loot** - All loot systems functional with smart defaults
6. **Mythic+** - Keystone system working with scaling and affixes
7. **Configuration** - All promised config options functional
8. **Tests** - Comprehensive test coverage for critical paths
