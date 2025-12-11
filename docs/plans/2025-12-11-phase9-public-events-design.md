# Phase 9: Public Events - System Design

**Created:** 2025-12-11

## Overview

WildStar's public events system provides dynamic, zone-wide content that players participate in collectively. This includes zone invasions, world bosses, territory control, and timed challenges.

---

## System Components

| System | Description |
|--------|-------------|
| 9.1 Event Manager | Event scheduling, triggers, lifecycle management |
| 9.2 Objectives | Kill counts, collection, defend, escort, survival |
| 9.3 Participation | Contribution tracking, tier rewards |
| 9.4 World Bosses | Spawn timers, multi-phase encounters, raid mechanics |
| 9.5 Zone Events | Invasion waves, territory control, escalation |
| 9.6 Rewards | Loot tables, currency, titles, achievements |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    BezgelorWorld.EventManager                    │
│  (GenServer - coordinates all public events across zones)        │
├─────────────────────────────────────────────────────────────────┤
│  - Event scheduling (timer-based, player-triggered)             │
│  - Active event tracking per zone                               │
│  - Phase transitions and objective management                    │
│  - Participant tracking and contribution                         │
│  - Reward distribution                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  BezgelorWorld.Zone.Instance                     │
│  (Per-zone GenServer - entity management)                        │
├─────────────────────────────────────────────────────────────────┤
│  - Broadcasts event packets to zone players                      │
│  - Spawns/despawns event creatures                               │
│  - Tracks event-specific entities (objects, bosses)              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BezgelorDb.PublicEvents                       │
│  (Context - database operations)                                 │
├─────────────────────────────────────────────────────────────────┤
│  - Event instance CRUD                                           │
│  - Participation records                                         │
│  - Completion history                                            │
│  - Schedule persistence                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      BezgelorData.Store                          │
│  (ETS - static event definitions)                                │
├─────────────────────────────────────────────────────────────────┤
│  - Event templates (phases, objectives, rewards)                 │
│  - World boss definitions                                        │
│  - Spawn locations and timers                                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9.1 Event Manager

### Responsibilities

1. **Scheduling** - Timer-based event triggers (hourly, daily, random window)
2. **Triggers** - Player-count triggers, quest triggers, chain triggers
3. **Lifecycle** - Pending → Active → (Complete | Failed | Cancelled)
4. **Coordination** - Manages multiple concurrent events across zones

### Event States

```
pending → active → completed
              ↓
           failed
              ↓
         cancelled
```

### State Machine

| State | Description | Transitions |
|-------|-------------|-------------|
| `pending` | Event created, not yet started | → `active` (timer/trigger) |
| `active` | Event in progress | → `completed`, `failed`, `cancelled` |
| `completed` | All objectives met | Terminal |
| `failed` | Time expired or fail condition | Terminal |
| `cancelled` | Admin cancelled or zone emptied | Terminal |

### Trigger Types

| Type | Description | Example |
|------|-------------|---------|
| `timer` | Fixed schedule | "Every 2 hours" |
| `random_window` | Random within time window | "Between 6pm-10pm" |
| `player_count` | Minimum players in zone | "When 10+ players present" |
| `quest_complete` | Triggered by quest completion | "After defending outpost" |
| `chain` | Previous event completion | "Phase 2 after Phase 1" |
| `manual` | Admin/GM triggered | Debug/testing |

### EventManager GenServer State

```elixir
%{
  # Active events by zone
  active_events: %{
    {zone_id, instance_id} => [event_instance_id, ...]
  },

  # Timer references for cleanup
  event_timers: %{
    event_instance_id => timer_ref
  },

  # Scheduled events (not yet triggered)
  scheduled_events: %{
    schedule_id => %{
      event_id: integer(),
      zone_id: integer(),
      trigger_type: atom(),
      next_trigger: DateTime.t(),
      config: map()
    }
  },

  # World boss spawn windows
  world_boss_timers: %{
    boss_id => %{
      zone_id: integer(),
      spawn_window_start: DateTime.t(),
      spawn_window_end: DateTime.t(),
      spawned: boolean()
    }
  }
}
```

---

## 9.2 Objectives

### Objective Types

| Type | Description | Progress Tracking |
|------|-------------|-------------------|
| `kill` | Kill N creatures of type | `{current: 0, target: 50, creature_ids: [1001, 1002]}` |
| `kill_boss` | Kill specific boss | `{current: 0, target: 1, boss_id: 5001}` |
| `collect` | Collect N items | `{current: 0, target: 20, item_id: 3001}` |
| `interact` | Interact with N objects | `{current: 0, target: 5, object_ids: [2001]}` |
| `defend` | Protect target for duration | `{health_remaining: 100, duration_ms: 120000}` |
| `escort` | Escort NPC to destination | `{checkpoint: 0, total_checkpoints: 3}` |
| `survive` | Stay alive for duration | `{elapsed_ms: 0, duration_ms: 180000}` |
| `territory` | Control points | `{controlled: 2, required: 3, points: [A, B, C]}` |
| `damage` | Deal N total damage | `{current: 0, target: 1000000}` |

### Objective Structure (Static Data)

```elixir
%{
  index: 0,
  type: :kill,
  target: 50,
  creature_ids: [1001, 1002],   # For kill objectives
  item_id: nil,                  # For collect objectives
  object_ids: [],                # For interact objectives
  duration_ms: nil,              # For timed objectives
  contribution_per_unit: 10,     # Points per kill/collect
  required_for_completion: true  # Must complete to advance phase
}
```

### Objective Progress (Runtime)

```elixir
%{
  "objectives" => [
    %{
      "index" => 0,
      "type" => "kill",
      "current" => 25,
      "target" => 50,
      "creature_ids" => [1001, 1002],
      "contribution_per_unit" => 10
    }
  ],
  "phase_start_time" => ~U[2025-12-11 10:00:00Z]
}
```

---

## 9.3 Participation

### Contribution System

Players earn contribution points through:

| Action | Base Points | Modifiers |
|--------|-------------|-----------|
| Kill creature | 10 | +5 if tagged first |
| Kill boss | 100 | +50 if top 3 damage |
| Collect item | 5 | - |
| Complete objective | 25 | Per objective |
| Healing done | 1 per 100 | Capped at 500 |
| Damage done | 1 per 200 | Capped at 500 |
| Time participated | 1 per 10s | - |

### Reward Tiers

| Tier | Contribution % | Rewards |
|------|----------------|---------|
| Gold | Top 10% or 500+ | Full loot table, bonus currency, title progress |
| Silver | Top 25% or 300+ | 75% loot table, standard currency |
| Bronze | Top 50% or 100+ | 50% loot table, reduced currency |
| Participation | Any | XP only, no loot |

### Participation Record

```elixir
%EventParticipation{
  event_instance_id: integer(),
  character_id: integer(),

  # Contribution tracking
  contribution_score: integer(),
  kills: integer(),
  damage_dealt: integer(),
  healing_done: integer(),
  objectives_completed: [integer()],

  # Timing
  joined_at: DateTime.t(),
  last_activity_at: DateTime.t(),

  # Rewards
  reward_tier: :gold | :silver | :bronze | :participation,
  rewards_claimed: boolean()
}
```

---

## 9.4 World Bosses

### World Boss Features

1. **Spawn Windows** - Random spawn within configurable time window
2. **Announcements** - Zone-wide and world-wide alerts
3. **Multi-Phase** - Boss transitions through phases at health thresholds
4. **Mechanics** - Special abilities, adds, enrage timers
5. **Shared Tap** - All participants get credit (no tagging)

### World Boss Definition (Static Data)

```elixir
%{
  id: 5001,
  name_text_id: 50001,
  creature_template_id: 10001,
  zone_id: 100,
  spawn_position: {1234.5, 567.8, 90.0},

  # Spawn timing
  spawn_window_hours: {18, 22},       # 6pm-10pm server time
  spawn_cooldown_hours: 24,           # Minimum between spawns
  despawn_timer_ms: 1800000,          # 30 min if not engaged

  # Combat
  phases: [
    %{
      health_threshold: 100,
      abilities: [:ground_slam, :cleave],
      add_spawns: []
    },
    %{
      health_threshold: 60,
      abilities: [:ground_slam, :cleave, :enrage],
      add_spawns: [{:creature_id, 1005, :count, 4}]
    },
    %{
      health_threshold: 30,
      abilities: [:ground_slam, :cleave, :enrage, :berserk],
      add_spawns: [{:creature_id, 1005, :count, 8}]
    }
  ],
  enrage_timer_ms: 600000,           # 10 minutes

  # Rewards
  loot_table_id: 9001,
  currency_reward: %{omnibits: 50, glory: 100},
  achievement_id: 8001,
  title_id: 7001
}
```

### World Boss State (Runtime)

```elixir
%{
  boss_id: 5001,
  entity_guid: 0xF000_0000_0000_0001,
  zone_id: 100,
  instance_id: 1,

  # Combat state
  current_phase: 0,
  health_percent: 100,
  enrage_timer_ref: reference(),
  despawn_timer_ref: reference(),

  # Participation
  engaged: false,
  engaged_at: nil,
  participants: MapSet.t(),           # Character IDs
  damage_dealt: %{character_id => damage}
}
```

---

## 9.5 Zone Events

### Zone Event Types

| Type | Description | Example |
|------|-------------|---------|
| `invasion` | Waves of enemies attack | Dominion invasion of Thayd |
| `defense` | Protect location/NPC | Defend the generator |
| `assault` | Capture enemy positions | Take the Strain outpost |
| `collection` | Zone-wide resource gathering | Gather primal essences |
| `hunt` | Kill roaming creatures | Eliminate rampaging beasts |
| `escort` | Group escort mission | Lead refugees to safety |

### Wave System (Invasion Events)

```elixir
%{
  event_id: 2001,
  type: :invasion,
  zone_id: 100,

  waves: [
    %{
      index: 0,
      spawns: [
        %{creature_id: 1001, count: 10, spawn_points: [:north, :south]},
        %{creature_id: 1002, count: 5, spawn_points: [:east]}
      ],
      duration_ms: 60000,              # Max time before next wave
      kill_threshold: 0.8              # 80% killed to advance
    },
    %{
      index: 1,
      spawns: [
        %{creature_id: 1001, count: 15, spawn_points: [:all]},
        %{creature_id: 1003, count: 2, spawn_points: [:center]}
      ],
      duration_ms: 90000,
      kill_threshold: 0.9
    },
    %{
      index: 2,
      spawns: [
        %{creature_id: 1004, count: 1, spawn_points: [:center]},  # Mini-boss
      ],
      duration_ms: 180000,
      kill_threshold: 1.0              # Must kill boss
    }
  ],

  # Escalation
  escalation_enabled: true,
  escalation_thresholds: [10, 25, 50],  # Player counts
  escalation_multipliers: [1.0, 1.5, 2.0]
}
```

### Territory Control

```elixir
%{
  event_id: 3001,
  type: :territory,
  zone_id: 200,

  control_points: [
    %{
      id: :alpha,
      name: "Northern Outpost",
      position: {100.0, 200.0, 50.0},
      capture_radius: 30.0,
      capture_time_ms: 15000,           # Time to capture
      decay_time_ms: 30000              # Time to lose if uncontested
    },
    %{
      id: :beta,
      name: "Central Tower",
      position: {150.0, 150.0, 55.0},
      capture_radius: 25.0,
      capture_time_ms: 20000,
      decay_time_ms: 45000
    },
    %{
      id: :gamma,
      name: "Southern Gate",
      position: {200.0, 100.0, 48.0},
      capture_radius: 35.0,
      capture_time_ms: 10000,
      decay_time_ms: 20000
    }
  ],

  victory_condition: :hold_all,         # Or :hold_majority, :hold_time
  hold_time_required_ms: 120000,        # 2 minutes
  total_duration_ms: 600000             # 10 minute event
}
```

### Spawn Points

```elixir
%{
  zone_id: 100,
  spawn_points: %{
    north: [{1100.0, 1500.0, 50.0}, {1150.0, 1480.0, 52.0}],
    south: [{1100.0, 900.0, 48.0}, {1080.0, 920.0, 49.0}],
    east: [{1400.0, 1200.0, 51.0}],
    west: [{800.0, 1200.0, 50.0}],
    center: [{1100.0, 1200.0, 55.0}],
    all: [...]  # All points combined
  }
}
```

---

## 9.6 Rewards

### Reward Types

| Type | Description |
|------|-------------|
| `xp` | Experience points |
| `gold` | Currency |
| `currency` | Special currencies (omnibits, glory, etc.) |
| `item` | Loot table roll |
| `reputation` | Faction standing |
| `achievement` | Achievement progress/completion |
| `title` | Title unlock |

### Reward Scaling

Rewards scale based on:
1. **Contribution tier** - Gold/Silver/Bronze/Participation
2. **Participant count** - More players = individual rewards reduced slightly
3. **Event difficulty** - Higher difficulty = better rewards
4. **Completion speed** - Bonus for fast completion

### Reward Formula

```elixir
def calculate_rewards(event, participation, participant_count) do
  base = event.rewards
  tier_multiplier = tier_multiplier(participation.reward_tier)
  count_multiplier = count_multiplier(participant_count)
  speed_bonus = speed_bonus(event)

  %{
    xp: floor(base.xp * tier_multiplier * count_multiplier * speed_bonus),
    gold: floor(base.gold * tier_multiplier * count_multiplier),
    currency: calculate_currency(base.currency, tier_multiplier),
    items: roll_loot(base.loot_table_id, participation.reward_tier),
    reputation: floor(base.reputation * tier_multiplier),
    achievement_progress: base.achievement_id,
    title: if(participation.reward_tier == :gold, do: base.title_id, else: nil)
  }
end

defp tier_multiplier(:gold), do: 1.0
defp tier_multiplier(:silver), do: 0.75
defp tier_multiplier(:bronze), do: 0.5
defp tier_multiplier(:participation), do: 0.25

defp count_multiplier(count) when count <= 10, do: 1.0
defp count_multiplier(count) when count <= 25, do: 0.9
defp count_multiplier(count) when count <= 50, do: 0.8
defp count_multiplier(_count), do: 0.7
```

### Loot Table Structure

```elixir
%{
  id: 9001,
  name: "World Boss - Metal Maw",

  guaranteed: [
    %{item_id: 50001, quantity: 1}       # Always drops
  ],

  rolls: [
    %{
      count: 2,                          # Roll twice on this table
      items: [
        %{item_id: 50002, weight: 100, quantity: 1},
        %{item_id: 50003, weight: 50, quantity: 1},
        %{item_id: 50004, weight: 10, quantity: 1}   # Rare
      ]
    }
  ],

  tier_bonuses: %{
    gold: %{extra_rolls: 1, rare_chance_bonus: 0.1},
    silver: %{extra_rolls: 0, rare_chance_bonus: 0.05},
    bronze: %{extra_rolls: 0, rare_chance_bonus: 0}
  }
}
```

---

## Database Schemas

### EventInstance

```elixir
schema "event_instances" do
  field :event_id, :integer
  field :zone_id, :integer
  field :instance_id, :integer, default: 1
  field :state, Ecto.Enum, values: [:pending, :active, :completed, :failed, :cancelled]
  field :current_phase, :integer, default: 0
  field :current_wave, :integer, default: 0
  field :phase_progress, :map, default: %{}
  field :participant_count, :integer, default: 0
  field :difficulty_multiplier, :float, default: 1.0
  field :started_at, :utc_datetime
  field :ends_at, :utc_datetime
  field :completed_at, :utc_datetime

  has_many :participations, EventParticipation
  timestamps(type: :utc_datetime)
end
```

### EventParticipation

```elixir
schema "event_participations" do
  belongs_to :event_instance, EventInstance
  belongs_to :character, Character

  field :contribution_score, :integer, default: 0
  field :kills, :integer, default: 0
  field :damage_dealt, :integer, default: 0
  field :healing_done, :integer, default: 0
  field :objectives_completed, {:array, :integer}, default: []

  field :reward_tier, Ecto.Enum, values: [:gold, :silver, :bronze, :participation]
  field :rewards_claimed, :boolean, default: false
  field :joined_at, :utc_datetime
  field :last_activity_at, :utc_datetime

  timestamps(type: :utc_datetime)
end
```

### EventCompletion

```elixir
schema "event_completions" do
  belongs_to :character, Character
  field :event_id, :integer

  field :completion_count, :integer, default: 1
  field :gold_count, :integer, default: 0
  field :silver_count, :integer, default: 0
  field :bronze_count, :integer, default: 0
  field :best_contribution, :integer, default: 0
  field :fastest_completion_ms, :integer
  field :last_completed_at, :utc_datetime

  timestamps(type: :utc_datetime)
end
```

### EventSchedule

```elixir
schema "event_schedules" do
  field :event_id, :integer
  field :zone_id, :integer
  field :enabled, :boolean, default: true

  field :trigger_type, Ecto.Enum, values: [:timer, :random_window, :player_count, :chain]
  field :trigger_config, :map, default: %{}

  # Timer trigger: {"interval_hours": 2, "offset_minutes": 30}
  # Random window: {"start_hour": 18, "end_hour": 22, "min_gap_hours": 4}
  # Player count: {"min_players": 10, "check_interval_ms": 60000}
  # Chain: {"after_event_id": 1001, "delay_ms": 30000}

  field :last_triggered_at, :utc_datetime
  field :next_trigger_at, :utc_datetime

  timestamps(type: :utc_datetime)
end
```

### WorldBossSpawn

```elixir
schema "world_boss_spawns" do
  field :boss_id, :integer
  field :zone_id, :integer

  field :state, Ecto.Enum, values: [:waiting, :spawned, :engaged, :killed]
  field :spawn_window_start, :utc_datetime
  field :spawn_window_end, :utc_datetime
  field :spawned_at, :utc_datetime
  field :killed_at, :utc_datetime
  field :next_spawn_after, :utc_datetime

  timestamps(type: :utc_datetime)
end
```

---

## Protocol Packets

### Client Packets

| Packet | Description |
|--------|-------------|
| `ClientEventList` | Request active events in zone |
| `ClientEventJoin` | Explicitly join event (auto-join on contribution) |
| `ClientEventLeave` | Leave event participation |
| `ClientEventContribute` | Turn in collected items |

### Server Packets

| Packet | Description |
|--------|-------------|
| `ServerEventList` | List of active events in zone |
| `ServerEventStart` | New event started in zone |
| `ServerEventUpdate` | Objective progress update |
| `ServerEventPhase` | Phase transition |
| `ServerEventWave` | Wave spawned (invasion) |
| `ServerEventComplete` | Event completed with rewards |
| `ServerEventFailed` | Event failed |
| `ServerWorldBossSpawn` | World boss spawned announcement |
| `ServerWorldBossPhase` | Boss phase transition |
| `ServerWorldBossKilled` | Boss killed announcement |
| `ServerContributionUpdate` | Personal contribution update |
| `ServerRewardTierUpdate` | Current reward tier changed |

---

## Static Data Files

### public_events.json

```json
[
  {
    "id": 1001,
    "name_text_id": 100001,
    "type": "invasion",
    "zone_id": 100,
    "duration_ms": 600000,
    "phases": [...],
    "objectives": [...],
    "rewards": {...}
  }
]
```

### world_bosses.json

```json
[
  {
    "id": 5001,
    "name_text_id": 150001,
    "creature_template_id": 10001,
    "zone_id": 100,
    "spawn_position": [1234.5, 567.8, 90.0],
    "spawn_window": {"start_hour": 18, "end_hour": 22},
    "spawn_cooldown_hours": 24,
    "phases": [...],
    "loot_table_id": 9001,
    "achievement_id": 8001
  }
]
```

### event_spawn_points.json

```json
[
  {
    "zone_id": 100,
    "points": {
      "north": [[1100.0, 1500.0, 50.0], [1150.0, 1480.0, 52.0]],
      "south": [[1100.0, 900.0, 48.0]],
      "center": [[1100.0, 1200.0, 55.0]]
    }
  }
]
```

### event_loot_tables.json

```json
[
  {
    "id": 9001,
    "name": "World Boss - Metal Maw",
    "guaranteed": [{"item_id": 50001, "quantity": 1}],
    "rolls": [
      {
        "count": 2,
        "items": [
          {"item_id": 50002, "weight": 100, "quantity": 1},
          {"item_id": 50003, "weight": 50, "quantity": 1}
        ]
      }
    ]
  }
]
```

---

## Integration Points

### With Combat System

- `SpellHandler` reports kills to `EventManager.record_kill/4`
- `CreatureManager` death triggers event objective updates
- Damage tracking feeds into contribution calculation

### With Quest System

- Quest completion can trigger events (`chain` trigger type)
- Events can grant quest progress
- Shared objective tracking for "kill X" quests during events

### With Achievement System

- Event completion broadcasts achievement events
- `{:event_complete, event_id, tier}` → Achievement progress
- `{:world_boss_kill, boss_id}` → Achievement unlock

### With Reputation System

- Event rewards include faction standing
- Zone events tied to faction (Exile vs Dominion)

### With Zone System

- `Zone.Instance` handles entity spawning for events
- Broadcasts go through zone to all players
- Spatial queries for territory control

---

## Implementation Order

1. **Database Layer** - Migration, schemas, context module
2. **Static Data** - JSON files, ETS loading
3. **EventManager GenServer** - Core lifecycle management
4. **Protocol Packets** - Client and server packets
5. **Basic Event Handler** - Join/leave/list operations
6. **Objective System** - Kill/collect tracking
7. **World Boss System** - Spawn windows, phases
8. **Wave System** - Invasion events
9. **Territory Control** - Capture mechanics
10. **Reward System** - Tier calculation, distribution
11. **Combat Integration** - Kill recording, damage tracking
12. **Testing** - Unit tests, integration tests

---

## Success Criteria

- [ ] Events can be triggered manually and by schedule
- [ ] Multiple objective types work correctly
- [ ] Participation tracking is accurate
- [ ] Reward tiers calculated correctly
- [ ] World bosses spawn in windows
- [ ] Wave-based events progress correctly
- [ ] Territory control functions
- [ ] All packets serialize/deserialize correctly
- [ ] Zone broadcasts reach all players
- [ ] Database persists event history
