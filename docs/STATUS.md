# Bezgelor Project Status

**Last Updated:** 2025-12-11

## Overview

Bezgelor is an Elixir port of NexusForever, a WildStar server emulator. The project follows an incremental phase-based approach organized as a Mix umbrella application with 9 apps.

## Phase Summary

| Phase | Name | Status | Completion |
|-------|------|--------|------------|
| 1 | Foundation | ✅ Complete | 100% |
| 2 | Protocol Layer | ✅ Complete | 100% |
| 3 | Authentication | ✅ Complete | 100% |
| 4 | Realm Server | ✅ Complete | 100% |
| 5 | Character Management | ✅ Complete | 100% |
| 6 | Core Gameplay (Combat) | ✅ Complete | 100% |
| 7 | Game Systems | ✅ Complete | 100% |
| 8 | Tradeskills | ✅ Complete | 100% |
| 9 | Public Events | ✅ Complete | 100% |
| 10 | Dungeons & Instances | ✅ Complete | 100% |
| 11 | PvP | ⏳ Not Started | 0% |

---

## Phase Details

### Phase 1: Foundation ✅

- Umbrella project structure
- Type system (Vector3, entities)
- Configuration management
- Process registry

### Phase 2: Protocol Layer ✅

- Binary packet parsing/serialization (PacketReader/PacketWriter)
- 70+ packet definitions across auth/realm/world
- TCP connection management with Ranch
- Packet framing (length-prefix, opcode parsing)
- Handler dispatch system

### Phase 3: Authentication ✅

- SRP6 zero-knowledge authentication
- Packet encryption/decryption
- Session ticket generation
- Account validation

### Phase 4: Realm Server ✅

- Realm selection
- Character list retrieval
- Session validation
- Server status broadcasting

### Phase 5: Character Management ✅

- Character creation with appearance
- Character selection
- Character deletion
- Initial spawn positioning

### Phase 6: Core Gameplay ✅

- Combat system (spells, damage, healing)
- Creature AI with threat tables
- XP and leveling
- Loot generation and distribution
- Death and respawn mechanics
- Buff/debuff system
- Cooldown management

---

## Phase 7: Game Systems

| System | Status | Description |
|--------|--------|-------------|
| 7.1 Chat | ✅ Complete | Say, yell, emote, party, guild, whisper, slash commands |
| 7.2 Inventory | ✅ Complete | Bags, equip, unequip, split stacks, destroy items |
| 7.3 Quests | ✅ Complete | Accept, track progress, turn in, abandon |
| 7.4 Social | ✅ Complete | Friends list, ignore list, online status |
| 7.5 Achievements | ✅ Complete | Achievement tracking, criteria progress, unlocks |
| 7.6 Paths | ✅ Complete | Soldier, Settler, Scientist, Explorer missions |
| 7.7 Guilds | ✅ Complete | Create, invite, ranks, permissions, bank, MOTD |
| 7.8 Mail | ✅ Complete | Send, receive, attachments, gold, COD, return to sender |
| 7.9 Mounts & Pets | ✅ Complete | Summon, dismiss, customize, pet XP from combat |
| 7.10 Housing | ✅ Complete | Plots, decor placement, fabkits, neighbors, roommates |
| 7.11 Storefront | ✅ Complete | Categories, purchases, promo codes, daily deals |
| 7.12 Reputation | ✅ Complete | Faction standing, thresholds, title unlocks, kill/quest rewards |

---

## Phase 10: Dungeons & Instances ✅

| Component | Status | Description |
|-----------|--------|-------------|
| 10.1 Instance Manager | ✅ Complete | Instance lifecycle, player tracking, lockouts |
| 10.2 Boss Encounters DSL | ✅ Complete | Declarative boss combat with phases, abilities, telegraphs |
| 10.3 Group Finder | ✅ Complete | Queue system, role matching, match confirmation |
| 10.4 Loot System | ✅ Complete | Personal loot, need/greed, master loot, round robin |
| 10.5 Mythic+ System | ✅ Complete | Keystones, affixes, timers, score calculation |
| 10.6 Protocol Layer | ✅ Complete | 20+ packets for instances, loot, group finder, mythic+ |

### Key Features

**Boss DSL Primitives:**
- `phase` - Phase transitions, intermissions
- `telegraph` - Circle, cone, donut, line, cross, wave AOEs
- `target` - Tank, healer, random, chain, spread, fixate
- `spawn` - Adds, waves, portals, split mechanics
- `movement` - Knockback, pull, charge, leap, teleport
- `interrupt` - Interrupt armor, MoO windows
- `environmental` - Void zones, fire, falling debris
- `coordination` - Stack, spread, pair, soak, tether

**Group Finder Matching:**
- FIFO matching for normal content
- Smart matching (gear score, wait time) for veteran
- Advanced matching (language groups, composition) for raids
- Role requirements: 1 tank + 1 healer + 3 DPS (dungeons)

**Mythic+ Affixes (12 defined):**
- Tier 1: Fortified, Tyrannical
- Tier 2: Bolstering, Raging, Sanguine, Inspiring
- Tier 3: Explosive, Quaking, Grievous, Volcanic, Necrotic
- Seasonal: Awakened

---

## Application Status

| App | Purpose | Status | Notes |
|-----|---------|--------|-------|
| bezgelor_core | Game logic | ✅ Complete | Entity, spell, AI, experience, loot systems |
| bezgelor_crypto | Security | ✅ Complete | SRP6, packet encryption, password hashing |
| bezgelor_db | Database | ✅ Complete | 43 Ecto schemas, 10+ migrations |
| bezgelor_protocol | Packets | ✅ Complete | 70+ packets, handlers, framing |
| bezgelor_auth | Auth server | ✅ Complete | Login flow, session management |
| bezgelor_realm | Realm server | ✅ Complete | Character list, realm selection |
| bezgelor_world | World server | ✅ Complete | All Phase 6-9 systems implemented |
| bezgelor_api | REST API | ✅ Complete | Status, player, zone endpoints |
| bezgelor_data | Static data | ✅ Complete | ETS store, tradeskill data, ETF compilation |

---

## Database Schemas (43 total)

### Core
- `account` - User accounts with SRP6 credentials
- `character` - Player characters with progression

### Character Data
- `character_appearance` - Visual customization
- `character_collection` - Unlocked items
- `inventory_item` - Character inventory
- `bag` - Bag slots and capacity

### Progression
- `quest` - Active quests
- `quest_history` - Completed quests
- `achievement` - Achievement progress
- `path` - Path selection
- `path_mission` - Mission progress
- `reputation` - Faction standing

### Social
- `friend` - Friends list
- `ignore` - Ignore list
- `mail` - Mail messages
- `mail_attachment` - Mail item attachments

### Guilds
- `guild` - Guild data
- `guild_member` - Membership
- `guild_rank` - Rank definitions
- `guild_bank_item` - Bank storage

### Housing
- `housing_plot` - Player plots
- `housing_decor` - Placed decorations
- `housing_fabkit` - Installed fabkits
- `housing_neighbor` - Neighbor permissions

### Account-wide
- `account_currency` - Premium currencies
- `account_collection` - Account unlocks
- `account_suspension` - Bans/suspensions
- `account_title` - Unlocked titles (account-wide)
- `active_mount` - Summoned mount
- `active_pet` - Summoned pet
- `store_item` - Store catalog
- `store_purchase` - Purchase history
- `store_category` - Store categories (hierarchical)
- `store_promotion` - Time-limited sales/bundles
- `promo_code` - Promotional codes
- `promo_redemption` - Code redemption tracking
- `daily_deal` - Rotating daily deals

### Public Events
- `event_instance` - Active event state
- `event_participation` - Character contribution tracking
- `event_completion` - Historical event completions
- `event_schedule` - Scheduled event times
- `world_boss_spawn` - Boss spawn history

---

## Test Coverage

- **Total test files:** 86+
- **bezgelor_crypto:** Comprehensive (SRP6, encryption verified)
- **bezgelor_protocol:** Good coverage (packet parsing, handlers)
- **bezgelor_core:** Good coverage (game logic)
- **bezgelor_world:** Moderate coverage (combat, creatures)
- **bezgelor_db:** Schema validation tests

---

## What Remains

Phase 10 (Dungeons & Instances) is complete. Next phase:

- **Phase 11: PvP** - Dueling, battlegrounds, arenas, warplots

---

## Phase 8: Tradeskills ✅ Complete

| System | Status | Description |
|--------|--------|-------------|
| 8.1 Database Schemas | ✅ Complete | CharacterTradeskill, SchematicDiscovery, TradeskillTalent, WorkOrder |
| 8.2 Context Module | ✅ Complete | Profession management, discovery, talents, work orders |
| 8.3 Coordinate System | ✅ Complete | Rectangle hit detection, overcharge mechanics |
| 8.4 Crafting Session | ✅ Complete | In-memory session state, additive tracking |
| 8.5 Gathering Nodes | ✅ Complete | Tap/respawn mechanics, availability checks |
| 8.6 Configuration | ✅ Complete | Server-configurable profession limits, node competition, respec policy |
| 8.7 Client Packets | ✅ Complete | 11 packets (learn, craft, gather, talents, work orders) |
| 8.8 Server Packets | ✅ Complete | 11 packets (lists, updates, results, discoveries) |
| 8.9 Handlers | ✅ Complete | TradeskillHandler, CraftingHandler, GatheringHandler |
| 8.10 Static Data | ✅ Complete | Professions, schematics, talents, additives, nodes, work orders |
| 8.11 ETS Integration | ✅ Complete | Tradeskill tables loaded into ETS store with query helpers |
| 8.12 Zone Integration | ✅ Complete | Handlers use ETS store for loot, XP, respawn data |

**Features:**
- 6 crafting professions: Weaponsmith, Armorer, Outfitter, Tailor, Technologist, Architect
- 3 gathering professions: Mining, Survivalist, Relic Hunter
- Coordinate-based crafting with 2D grid and quality zones
- Overcharge system (0-3 levels with multipliers and failure risk)
- Talent trees with prerequisites and tier unlocks
- Gathering nodes with loot tables and respawn timers
- Work orders for daily profession quests
- Additive system to shift crafting cursor
- Full ETS integration for static data lookup

---

## Phase 9: Public Events ✅ Complete

| System | Status | Description |
|--------|--------|-------------|
| 9.1 Event Manager | ✅ Complete | Event scheduling, triggers, lifecycle via GenServer |
| 9.2 Objectives | ✅ Complete | Kill counts, collection, defend/escort, boss kills |
| 9.3 Participation | ✅ Complete | Contribution tracking, tier-based rewards (gold/silver/bronze) |
| 9.4 World Bosses | ✅ Complete | Spawn timers, multi-phase encounters, enrage, damage tracking |
| 9.5 Zone Events | ✅ Complete | Invasion waves, territory control with capture mechanics |
| 9.6 Rewards | ✅ Complete | XP, gold, currency, loot tables, achievements, titles |

**Features:**
- **EventManager GenServer:** Per-zone instance with Registry-based naming
- **Event Types:** Invasion, collection, territory control, world boss
- **Objective System:** Kill, collect, defend, escort, kill_boss with progress tracking
- **Wave System:** Sequential spawns with timer-based advancement
- **Territory Control:** Capture points, progress decay, majority win conditions
- **World Bosses:** Multi-phase health thresholds, add spawns, enrage timers
- **Contribution Tracking:** Per-character contribution with tier thresholds
- **Reward Distribution:** Tier-based rewards (gold > 75%, silver > 50%, bronze > 25%)
- **Combat Integration:** Kill notifications update event objectives automatically
- **Supervision:** DynamicSupervisor manages EventManager instances per zone

**Database Schemas:**
- `event_instance` - Active event state, phase, progress
- `event_participation` - Character contribution tracking
- `event_completion` - Historical event completions
- `event_schedule` - Scheduled event times
- `world_boss_spawn` - Boss spawn history

**Packets:**
- Client: JoinEvent, LeaveEvent, ListEvents, ContributeToEvent
- Server: EventList, EventUpdate, EventComplete, WorldBossSpawn, WorldBossPhase, WorldBossDeath

---

## Phase 11: PvP ⏳ Not Started

| System | Status | Description |
|--------|--------|-------------|
| 11.1 Dueling | ⏳ Pending | Challenge, accept, boundaries, victory |
| 11.2 Battlegrounds | ⏳ Pending | Walatiki Temple, Halls of the Bloodsworn |
| 11.3 Arenas | ⏳ Pending | 2v2, 3v3, 5v5 rated matches |
| 11.4 Warplots | ⏳ Pending | 40v40 fortress warfare |
| 11.5 PvP Gear | ⏳ Pending | PvP stats, conquest vendors |
| 11.6 Rating System | ⏳ Pending | ELO/MMR, seasons, rewards |

**Implementation Steps:**
1. Create `pvp_stats` schema (kills, deaths, rating per bracket)
2. Create `arena_team` schema (team roster, rating, history)
3. Create `warplot` schema (warplot ownership, upgrades)
4. Create `battleground_queue` schema (queue state, matchmaking)
5. Implement duel system (challenge, countdown, boundaries)
6. Add battleground instance management (maps, objectives, scoring)
7. Implement arena matchmaking (rating-based pairing)
8. Add PvP combat modifications (resilience, PvP power)
9. Implement rating calculations (win/loss adjustments)
10. Add season tracking and reward distribution
11. Implement warplot building and plug system
12. Add conquest currency and PvP vendor integration

---

## Architecture Highlights

- **Elixir/OTP:** GenServers, supervision trees, ETS caching
- **Ecto:** PostgreSQL with comprehensive schema design
- **Ranch:** TCP connection handling
- **Phoenix:** REST API endpoints
- **Binary protocol:** Bit-level packet parsing matching WildStar format

---

## Key Directories

```
apps/
├── bezgelor_api/        # REST API (Phoenix)
├── bezgelor_auth/       # Authentication server
├── bezgelor_core/       # Game logic (pure functions)
├── bezgelor_crypto/     # Cryptography (SRP6, encryption)
├── bezgelor_data/       # Static game data
├── bezgelor_db/         # Database layer (Ecto)
├── bezgelor_protocol/   # Packet definitions
├── bezgelor_realm/      # Realm server
└── bezgelor_world/      # World server

docs/
├── plans/               # Phase planning documents
├── games/wildstar/      # WildStar research & data
└── STATUS.md            # This file

tools/
└── tbl_extractor/       # Game data extraction scripts
```

---

## Recent Completions

- **2025-12-11:** Phase 7 Finalization - ClientGiftItem, ClientRedeemCode, ServerPromoCodeResult packets with handler methods
- **2025-12-11:** Phase 10 Finalization - LockoutManager/MythicManager GenServers in supervision tree, 8 schema unit test files (226 tests)
- **2025-12-11:** Phase 9 Public Events Complete - EventManager, objectives, world bosses, territory control, rewards
- **2025-12-11:** Phase 8 Tradeskills Complete - ETS integration, static data files, all handlers functional
- **2025-12-11:** Phase 8 Tradeskills 60% - Core systems complete (schemas, handlers, packets, coordinate crafting)
- **2025-12-10:** Phase 7 Complete! System 12 (Reputation - title system, kill/quest rewards, level tracking)
- **2025-12-10:** Phase 7 System 11 (Storefront - categories, promotions, promo codes, daily deals)
- **2025-12-10:** Phase 7 Systems 9-10 (Mounts & Pets handlers, Housing complete)
- **2025-12-10:** Phase 6 polish (edge case tests, AI optimization, loot broadcasting)
- **2025-12-09:** Phase 7 Systems 7 (Guilds) and 8 (Mail)
- **2025-12-08:** Phase 7 Systems 1-6 (Chat, Inventory, Quests, Social, Achievements, Paths)
