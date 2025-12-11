# Bezgelor Project Status

**Last Updated:** 2025-12-10

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
| 7 | Game Systems | 🔄 In Progress | ~83% |

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
| 7.11 Storefront | ⏳ Pending | Purchases, account currency, unlocks |
| 7.12 Reputation | ⏳ Pending | Faction standing, thresholds, rewards |

---

## Application Status

| App | Purpose | Status | Notes |
|-----|---------|--------|-------|
| bezgelor_core | Game logic | ✅ Complete | Entity, spell, AI, experience, loot systems |
| bezgelor_crypto | Security | ✅ Complete | SRP6, packet encryption, password hashing |
| bezgelor_db | Database | ✅ Complete | 32 Ecto schemas, 10+ migrations |
| bezgelor_protocol | Packets | ✅ Complete | 70+ packets, handlers, framing |
| bezgelor_auth | Auth server | ✅ Complete | Login flow, session management |
| bezgelor_realm | Realm server | ✅ Complete | Character list, realm selection |
| bezgelor_world | World server | 🔄 95% | Core gameplay + most systems done, storefront/reputation pending |
| bezgelor_api | REST API | ✅ Complete | Status, player, zone endpoints |
| bezgelor_data | Static data | 🔄 60% | ETS store, ETF compilation, text extraction |

---

## Database Schemas (32 total)

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
- `active_mount` - Summoned mount
- `active_pet` - Summoned pet
- `store_item` - Store catalog
- `store_purchase` - Purchase history

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

### Phase 7 Pending Systems

1. **Storefront** (~800 LOC)
   - Item catalog display
   - Purchase flow
   - Account currency handling
   - Account-wide unlocks

2. **Reputation** (~400 LOC)
   - Faction gains from kills/quests
   - Standing thresholds
   - Reputation-gated vendors
   - Title unlocks

### Future Phases (Not Started)

- **Phase 8: Tradeskills** - Crafting, gathering, schematics
- **Phase 9: Public Events** - World events, group objectives
- **Phase 10: Dungeons** - Instance management, boss mechanics
- **Phase 11: PvP** - Battlegrounds, arenas, war plots

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

- **2025-12-10:** Phase 7 Systems 9-10 (Mounts & Pets handlers, Housing complete)
- **2025-12-10:** Phase 6 polish (edge case tests, AI optimization, loot broadcasting)
- **2025-12-09:** Phase 7 Systems 7 (Guilds) and 8 (Mail)
- **2025-12-08:** Phase 7 Systems 1-6 (Chat, Inventory, Quests, Social, Achievements, Paths)
