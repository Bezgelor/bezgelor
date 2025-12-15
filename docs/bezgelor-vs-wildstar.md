# Bezgelor vs WildStar Differences

This document tracks intentional differences between Bezgelor and the original WildStar game. These changes are made for improved player experience, server administration, or technical reasons.

## Character Creation

### All Experience Levels Unlocked

**Original Behavior:** The Veteran and Level 50 character creation experiences required account progression to unlock:
- Veteran (Nexus start): Required level 3+ character or tutorial completion
- Level 50 start: Required level 50 character and MaxLevelToken currency

**Bezgelor Behavior:** All character creation experiences are always available from the start. The `ServerMaxCharacterLevelAchieved` packet always reports level 50, unlocking all options.

**Rationale:** For a private server environment, players shouldn't need to grind through content they've already experienced just to unlock creation options. This is especially relevant for returning players or those testing different race/class combinations.

**Note:** The Level 50 start still requires MaxLevelToken currency to use (not yet implemented).

**Files Changed:**
- `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_list_handler.ex`

---

## Character Display

### Gear Mask Backward Compatibility

**Original Behavior:** The `gear_mask` field on characters is a bitmask where:
- Set bit (1) = gear slot visible
- Clear bit (0) = gear slot hidden
- `0xFFFFFFFF` = all gear visible
- `0x00000000` = all gear hidden

**Bezgelor Behavior:** A `gear_mask` value of `0` is treated as "all visible" (`0xFFFFFFFF`) for backward compatibility with older database records that defaulted to 0.

**Rationale:** Early character records were created before the gear_mask system was implemented and have a default value of 0. Rather than requiring a data migration, we handle this edge case in code.

**Implementation Note:** PostgreSQL uses signed integers, so the "all visible" value is stored as `-1` (which equals `0xFFFFFFFF` in two's complement) and converted to unsigned when sent to the client.

**Files Changed:**
- `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_character_list.ex`
- `apps/bezgelor_db/lib/bezgelor_db/schema/character.ex`

---

## Creature Patrol System

### Automatic Spline-Based Patrol Assignment

**Original Behavior:** WildStar stored explicit entity-to-spline mappings in a server-side `entity_spline` database table. Each patrolling creature had a manual assignment linking its entity ID to a specific spline ID.

**Bezgelor Behavior:** Patrol paths are automatically assigned based on proximity. When a creature spawns, the system searches for splines within 15 units of the spawn position. If found, the creature automatically patrols that route.

**Data Sources:**
- **13,304 splines** with **380,576 waypoints** extracted from WildStar client files (`Spline2.tbl`, `Spline2Node.tbl`)
- Splines include patrol routes, taxi paths, scripted event movements, and quest NPC paths

**Coverage:**
| Zone | Patrolling | Total | Rate |
|------|------------|-------|------|
| Destiny (Dominion Tutorial) | 2 | 2 | 100% |
| NorthernWilds | 129 | 534 | 24.2% |
| Blighthaven (+4 more) | 1,299 | 14,732 | 8.8% |
| CrimsonIsle | 70 | 816 | 8.6% |
| Algoroc (+4 more) | 2,262 | 16,174 | 14.0% |
| EverstarGrove | 113 | 975 | 11.6% |
| Auroria (+4 more) | 1,522 | 13,863 | 11.0% |
| LevianBay | 169 | 937 | 18.0% |
| **TOTAL** | **5,584** | **48,095** | **11.6%** |

**Manual Override Options:**
- `spline_id: 123` - Explicitly assign a client spline by ID
- `patrol_path: "name"` - Use a custom-defined patrol from `patrol_paths.json`
- `auto_spline: false` - Disable automatic patrol matching for specific spawns

**Rationale:** The original entity_spline database was empty in NexusForever (meant to be manually populated). Automatic proximity matching provides reasonable patrol coverage without manual configuration. The 15-unit threshold was chosen to balance coverage (~11.6%) against false positives.

**How It Works:**
1. On spawn, `build_ai_options` searches for splines within 15 units
2. If found, patrol waypoints are passed to `AI.new`
3. `AI.new` sets `patrol_enabled: true` when waypoints are provided
4. The tick loop processes idle creatures with patrol enabled
5. `AI.tick` returns `{:start_patrol, ai}` to begin movement
6. Patrol state machine handles waypoint navigation, pausing, and cycling

**Files Changed:**
- `apps/bezgelor_data/lib/bezgelor_data/store.ex` - Spline loading and proximity search
- `apps/bezgelor_data/priv/data/Spline2.json` - 13,304 spline definitions
- `apps/bezgelor_data/priv/data/Spline2Node.json` - 380,576 waypoints
- `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex` - Auto-assignment and tick processing
- `apps/bezgelor_world/lib/bezgelor_world/creature/zone_manager.ex` - Auto-assignment and tick processing
- `apps/bezgelor_core/lib/bezgelor_core/ai.ex` - Patrol state machine

---

## Optimizations

These are performance optimizations that may differ from original WildStar server behavior but don't affect gameplay.

### Zone-Based AI Processing

**Original Behavior:** Unknown. The original WildStar server implementation details are not available.

**Bezgelor Behavior:** Creature AI is only processed for zones that have active players. Creatures in empty zones remain idle until a player enters.

**How It Works:**
1. `TickScheduler` broadcasts tick messages to registered listeners every second
2. `CreatureManager` receives tick notifications and queries `InstanceSupervisor.list_zones_with_players()`
3. Only creatures in zones with players (or creatures already in combat) are processed
4. The active zone set is a `MapSet` for O(1) membership checking

**Exception:** Creatures in combat or evading states continue processing even if all players leave the zone, ensuring they properly reset to their spawn positions.

**Performance Impact:** With 48,000+ creatures across all zones but only ~100-500 in zones with players, this reduces per-tick processing by 99%+ when few zones are active.

**Files Changed:**
- `apps/bezgelor_world/lib/bezgelor_world/creature_manager.ex` - Zone filtering in `process_ai_tick/1`
- `apps/bezgelor_world/lib/bezgelor_world/zone/instance_supervisor.ex` - `list_zones_with_players/0`

---

## Future Differences

This section will be updated as more intentional deviations are implemented.

### Planned Changes

- **XP Rates:** Configurable XP multipliers (not yet implemented)
- **Drop Rates:** Configurable loot multipliers (not yet implemented)
- **Reputation Gains:** Configurable reputation multipliers (not yet implemented)

---

## Technical Differences

These are implementation details that don't affect gameplay but differ from the original server.

### Database

- Single shared database for all realms (original had separate databases)
- PostgreSQL instead of MySQL/MariaDB

### Architecture

- Elixir/OTP instead of ... whatever it was, C++?
- Process-per-player model with message passing
- ETS for static game data instead of in-memory caching

---

## Contributing

When making intentional changes that deviate from original WildStar behavior, please document them here with:
1. Original behavior description
2. Bezgelor behavior description
3. Rationale for the change
4. Files changed
