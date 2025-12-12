# Bezgelor: WildStar Server Emulator in Elixir

**Date:** 2025-12-09
**Status:** Approved
**Source:** NexusForever (C# implementation)

## Overview

Bezgelor is a full port of NexusForever (WildStar MMORPG server emulator) from C# to Elixir. The goal is to create an idiomatic Elixir implementation that leverages OTP for concurrency and fault tolerance, serving as a foundation for LLM-driven development of additional features.

### Motivation

1. **Concurrency/Scalability** — BEAM's actor model handles thousands of concurrent players naturally
2. **Fault Tolerance** — OTP supervision trees provide automatic recovery without infrastructure overhead
3. **Learning** — Explore Elixir/OTP through a substantial, real-world project

### Scope

- Full faithful port of NexusForever functionality
- Idiomatic Elixir (not literal C# translation)
- No microservices or message bus — leverage OTP instead
- Foundation for future LLM-driven feature development

---

## Architecture

### High-Level Structure

Bezgelor is an Elixir **umbrella application** with the following apps:

```
bezgelor/
├── apps/
│   ├── bezgelor_core/        # Shared utilities, types, config
│   ├── bezgelor_crypto/      # Encryption, packet encoding/decoding
│   ├── bezgelor_protocol/    # WildStar network protocol definitions
│   ├── bezgelor_data/        # Static game data (tables, definitions)
│   ├── bezgelor_db/          # Ecto repos, schemas, migrations
│   ├── bezgelor_game/        # Core game logic (entities, spells, combat)
│   ├── bezgelor_auth/        # Authentication server
│   ├── bezgelor_world/       # World server (zones, players, NPCs)
│   ├── bezgelor_chat/        # Chat system
│   ├── bezgelor_guild/       # Guild management
│   ├── bezgelor_api/         # Phoenix REST API
│   └── bezgelor_sts/         # Security Token Service
├── scripts/                  # Lua game scripts
├── config/                   # Environment configs
├── rel/                      # Release configuration
└── mix.exs                   # Umbrella mix file
```

**Key difference from NexusForever:** Instead of 7 separate server processes communicating via RabbitMQ, this is **one BEAM application** with multiple supervision trees. The apps are organizational boundaries, not deployment units.

### OTP Supervision Tree

```
Bezgelor.Application (root supervisor)
├── Bezgelor.DB.Supervisor
│   ├── Bezgelor.DB.AuthRepo          # Database connection pool (auth)
│   ├── Bezgelor.DB.CharacterRepo     # Database connection pool (characters)
│   └── Bezgelor.DB.WorldRepo         # Database connection pool (world)
├── Bezgelor.Data.Supervisor
│   └── Bezgelor.Data.GameTables      # Static game data loaded into ETS
├── Bezgelor.Auth.Supervisor
│   ├── Bezgelor.Auth.SessionManager  # Tracks active auth sessions
│   └── Bezgelor.Auth.Listener        # TCP listener for auth connections
├── Bezgelor.World.Supervisor
│   ├── Bezgelor.World.ZoneSupervisor # Dynamic supervisor for zones
│   │   └── Zone:<id>                 # One process per active zone
│   ├── Bezgelor.World.PlayerSupervisor
│   │   └── Player:<id>               # One process per connected player
│   └── Bezgelor.World.Listener       # TCP listener for world connections
├── Bezgelor.Chat.Supervisor
│   └── Bezgelor.Chat.ChannelManager  # Chat channel processes
└── Bezgelor.Api.Endpoint             # Phoenix HTTP endpoint
```

### Process Model

| Concept | Process Type | State Held |
|---------|--------------|------------|
| Connected player | GenServer | Position, inventory, spells, buffs, current zone |
| Zone instance | GenServer | All entities in zone, spawn timers, event state |
| NPC/Creature | Part of Zone state | Health, position, AI state |
| Guild | GenServer | Members, ranks, bank, perks |
| Chat channel | GenServer | Subscribers, message history |

**Key principle:** Each player is a process. When something happens in a zone, the zone process sends messages to relevant player processes. No shared mutable state, no locks, no race conditions.

---

## Technology Decisions

### Database: PostgreSQL with Ecto

Multiple Ecto repositories for logical separation:

- `Bezgelor.DB.AuthRepo` — Accounts, sessions, bans
- `Bezgelor.DB.CharacterRepo` — Characters, items, quests
- `Bezgelor.DB.WorldRepo` — World state, guilds

Repositories can point to same or different databases (configuration choice).

### Network Protocol: Custom TCP with Ranch

- **`ranch`** — Erlang TCP acceptor library (used by Phoenix internally)
- **Binary parsing** — Elixir's `<<>>` pattern matching for packet decoding
- **Connection process** — One GenServer per connected client
- **Encryption** — Ported from NexusForever's cryptography module

### HTTP API: Phoenix (Minimal)

Phoenix used only for:
- REST API endpoints (character list, server status)
- Admin tooling (future)

Game client communication uses custom binary protocol over TCP, not Phoenix Channels.

### Static Game Data: ETS Tables

Game tables (items, spells, creatures, etc.) loaded into ETS on startup:
- `read_concurrency: true` for parallel reads
- No message passing overhead for lookups
- Data loaded from exported NexusForever files

### Scripting: Lua via luerl

Zone events, quest behaviors, and instance mechanics implemented in Lua:

**Pros:**
- Sandboxed execution (can't crash BEAM)
- Industry standard for game scripting
- Familiar to content creators
- LLM-friendly (abundant training data)
- Hot reload without compilation

**Implementation:**
- Elixir exposes safe API to Lua (`game.spawn_creature`, `game.send_message`, etc.)
- Scripts stored in `scripts/` directory
- Zone, quest, and instance behaviours call Lua handlers

---

## Game Logic Structure

```
apps/bezgelor_game/lib/
├── bezgelor_game.ex              # Public API
├── entity/
│   ├── entity.ex                 # Base entity behavior
│   ├── player.ex                 # Player-specific logic
│   ├── creature.ex               # NPC/mob logic
│   └── properties.ex             # Stat calculations
├── combat/
│   ├── combat.ex                 # Combat resolution
│   ├── damage.ex                 # Damage calculation
│   └── threat.ex                 # Threat/aggro system
├── spell/
│   ├── spell.ex                  # Spell casting
│   ├── effect.ex                 # Spell effects
│   └── cooldown.ex               # Cooldown tracking
├── quest/
│   ├── quest.ex                  # Quest state machine
│   ├── objective.ex              # Objective tracking
│   └── reward.ex                 # Reward distribution
├── inventory/
│   ├── inventory.ex              # Bag management
│   ├── item.ex                   # Item operations
│   └── equipment.ex              # Equip/unequip
└── social/
    ├── mail.ex                   # Mail system
    ├── friend.ex                 # Friends list
    └── ignore.ex                 # Ignore list
```

**Key pattern:** Pure functions for game logic, GenServers for state management. This separation makes the codebase highly testable.

---

## Testing Strategy

### Test Layers

| Layer | Test Type | Example |
|-------|-----------|---------|
| Pure functions | Unit tests | `Damage.calculate/3` returns correct value |
| GenServers | Process tests | Player process handles `:move` message correctly |
| Protocol | Parsing tests | Binary packet decodes to correct struct |
| Database | Integration | Character saves and loads correctly |
| Lua scripts | Script tests | Zone script fires correct events |
| Full flows | End-to-end | Client connects → authenticates → enters world |

### Test Organization

```
apps/
├── bezgelor_core/test/
├── bezgelor_game/test/
│   ├── combat/
│   │   ├── damage_test.exs
│   │   └── threat_test.exs
│   └── spell/
│       └── spell_test.exs
├── bezgelor_protocol/test/
│   └── parser_test.exs
└── test/                         # Integration tests (umbrella level)
    ├── auth_flow_test.exs
    ├── character_create_test.exs
    └── combat_integration_test.exs
```

---

## Implementation Phases

### Phase 1: Foundation
- Umbrella project structure
- `bezgelor_core` — Config, logging, common types
- `bezgelor_crypto` — Packet encryption/decryption
- `bezgelor_db` — Ecto repos, account/character schemas, migrations
- Basic supervision tree

### Phase 2: Protocol Layer
- `bezgelor_protocol` — Packet definitions, binary parsing
- TCP listener with `ranch`
- Connection process handling handshake
- **Milestone:** Client connects, packets parse correctly

### Phase 3: Authentication
- `bezgelor_auth` — Login flow, session management
- `bezgelor_sts` — Security Token Service
- Account creation, password verification
- **Milestone:** Full login with real WildStar client

### Phase 4: Character Management
- Character creation, selection, deletion
- `bezgelor_api` — Phoenix REST API for character list
- **Milestone:** Create character, select, enter world

### Phase 5: World Entry
- `bezgelor_world` — Zone processes, player processes
- `bezgelor_data` — Load static game tables into ETS
- Player spawns in zone, can see environment
- **Milestone:** Character loads into world

### Phase 6: Core Gameplay
- `bezgelor_game` — Movement, entities, basic combat
- NPCs spawn, player can move and attack
- **Milestone:** Kill a creature, gain XP

### Phase 7: Systems (iterative)
- Chat, guilds, mail, quests, inventory, housing...
- Each system added incrementally
- Lua scripting integration

---

## Key Patterns for LLM Development

The codebase establishes consistent patterns for LLM-driven feature development:

1. **Module structure** — Each system follows the same organization
2. **Behaviours** — Clear contracts for extensible components
3. **Pure functions** — Game logic separated from state management
4. **Typespecs** — All public functions have `@spec` annotations
5. **Documentation** — Module and function docs explain intent
6. **Tests** — Each module has corresponding test file

Future LLM work will:
1. Read existing patterns in the codebase
2. Implement new features following those patterns
3. Write tests following existing test patterns
4. Generate Lua scripts for content

---

## What This Is NOT

- **Not a literal translation** — C# idioms replaced with Elixir idioms
- **Not microservices** — One BEAM application with internal boundaries
- **Not using Phoenix Channels** — Custom binary TCP for game protocol
- **Not using a message bus** — Direct process messaging via OTP
