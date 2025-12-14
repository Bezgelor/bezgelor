# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Bezgelor is a WildStar MMORPG server emulator written in Elixir, ported from NexusForever (C#). It's an Elixir umbrella application using OTP for concurrency and fault tolerance.

## Build & Test Commands

```bash
# Install dependencies
mix deps.get

# Compile all apps
mix compile

# Run all tests (excludes database tests by default)
mix test

# Run tests for a specific app
mix test apps/bezgelor_core/test/
mix test apps/bezgelor_db/test/

# Run a single test file
mix test apps/bezgelor_core/test/spell_test.exs

# Include database tests (requires PostgreSQL)
mix test --include database

# Database setup
mix ecto.create
mix ecto.migrate

# Reset database
mix ecto.reset
```

## Database

PostgreSQL on port 5433 (non-standard). Configuration via environment variables:
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`

Database tests use Ecto sandbox mode and are excluded by default (tagged `@moduletag :database`).

## Architecture

### Umbrella Apps

| App | Purpose |
|-----|---------|
| `bezgelor_core` | Shared types (Vector3, Entity), game logic (Spell, Combat, AI, XP) |
| `bezgelor_crypto` | SRP6 auth, packet encryption, password handling |
| `bezgelor_protocol` | WildStar binary protocol - packets, framing, handlers, TCP listeners |
| `bezgelor_db` | Ecto schemas, migrations, context modules (Accounts, Characters, Guilds, etc.) |
| `bezgelor_data` | Static game data loaded into ETS (creatures, spells, items, zones) |
| `bezgelor_auth` | Auth server (STS) on port 6600 |
| `bezgelor_realm` | Realm server on port 23115 |
| `bezgelor_world` | World server on port 24000 - zones, players, combat |
| `bezgelor_api` | Phoenix REST API |

### Key Patterns

**Contexts (bezgelor_db)**: Domain modules like `BezgelorDb.Accounts`, `BezgelorDb.Characters`, `BezgelorDb.Guilds` provide the public API for database operations. Each has corresponding schema modules in `lib/bezgelor_db/schema/`.

**Packets (bezgelor_protocol)**: Implement `Readable` and/or `Writable` behaviours. Located in `lib/bezgelor_protocol/packets/{realm,world}/`. Use `PacketReader`/`PacketWriter` for binary parsing.

**Handlers (bezgelor_protocol)**: Process incoming packets. Located in `lib/bezgelor_protocol/handler/`. Pattern: receive packet → validate → call context → send response packets.

**Zone Instances (bezgelor_world)**: GenServers managing entities, spawns, and broadcasts. One process per active zone.

**Game Logic (bezgelor_core)**: Pure functions for calculations (damage, XP, loot). State management handled by GenServers in bezgelor_world.

### Process Model

- Each connected player is a process
- Each active zone is a process
- Communication via message passing, no shared state
- Supervision trees for fault tolerance

## Data Extraction

Python tools in `tools/tbl_extractor/` extract WildStar game data:

```bash
# Extract .tbl files to JSON
python tools/tbl_extractor/tbl_extractor.py Creature2.tbl

# Extract localized text
python tools/tbl_extractor/language_extractor.py en-US.bin
```

Static data lives in `apps/bezgelor_data/priv/data/` as JSON, loaded into ETS on startup.

## Server Ports

| Server | Default Port |
|--------|-------------|
| Auth (STS) | 6600 |
| Realm | 23115 |
| World | 24000 |

## Implementation Status

Phases 1-6 complete. Phase 7 (Game Systems) in progress: Social, Reputation, Inventory, Quests, Achievements, Paths, Guilds, Mail complete. Mounts/Pets/Storefront next.

Plans and design docs in `docs/plans/`.
- NexusForever source is at ../nexusforever/
- NexusForever source is at ../nexusforever/
- NexusForever source is at ../nexusforever/