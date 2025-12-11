# Bezgelor

A WildStar MMORPG server emulator written in Elixir, ported from [NexusForever](https://github.com/NexusForever/NexusForever) (C#).

## Overview

Bezgelor is an Elixir umbrella application that emulates WildStar game servers using OTP for concurrency and fault tolerance. The project implements the full server stack including authentication, realm selection, and world gameplay.

## Features

- **Authentication** - SRP6 zero-knowledge authentication with packet encryption
- **Character Management** - Creation, customization, selection, and deletion
- **Combat System** - Spells, damage, healing, creature AI with threat tables
- **Progression** - XP, leveling, achievements, paths, reputation
- **Social** - Chat, friends, guilds, mail system
- **Housing** - Player plots, decor placement, fabkits, neighbors
- **Tradeskills** - 6 crafting + 3 gathering professions with coordinate-based crafting
- **Public Events** - World bosses, invasions, territory control
- **Dungeons** - Instance management, boss encounters DSL, group finder, loot distribution
- **Mythic+** - Keystones, affixes, timers, score calculation

## Architecture

### Umbrella Apps

| App | Purpose |
|-----|---------|
| `bezgelor_core` | Game logic - entities, spells, combat, AI, XP |
| `bezgelor_crypto` | SRP6 authentication, packet encryption |
| `bezgelor_protocol` | WildStar binary protocol - packets, framing, handlers |
| `bezgelor_db` | Ecto schemas and database operations |
| `bezgelor_data` | Static game data loaded into ETS |
| `bezgelor_auth` | Authentication server (port 6600) |
| `bezgelor_realm` | Realm server (port 23115) |
| `bezgelor_world` | World server (port 24000) |
| `bezgelor_api` | Phoenix REST API |

### Key Patterns

- **Contexts** - Domain modules (`BezgelorDb.Accounts`, `BezgelorDb.Characters`, etc.) provide the public API
- **Packets** - Implement `Readable`/`Writable` behaviours for binary protocol parsing
- **Handlers** - Process incoming packets and dispatch responses
- **Zone Instances** - GenServers managing entities, spawns, and broadcasts per zone
- **Supervision Trees** - OTP supervision for fault tolerance

## Requirements

- Elixir 1.15+
- PostgreSQL 14+ (configured on port 5433)
- WildStar game client data files

## Setup

```bash
# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.create
mix ecto.migrate

# Run the server
iex -S mix
```

## Configuration

Environment variables:
- `POSTGRES_DB` - Database name
- `POSTGRES_USER` - Database user
- `POSTGRES_PASSWORD` - Database password
- `POSTGRES_HOST` - Database host (default: localhost)
- `POSTGRES_PORT` - Database port (default: 5433)

## Testing

```bash
# Run all tests (excludes database tests)
mix test

# Run tests for a specific app
mix test apps/bezgelor_core/test/

# Include database tests
mix test --include database
```

## Data Extraction

Python tools in `tools/tbl_extractor/` extract WildStar game data:

```bash
# Extract .tbl files to JSON
python tools/tbl_extractor/tbl_extractor.py Creature2.tbl

# Extract localized text
python tools/tbl_extractor/language_extractor.py en-US.bin
```

## Project Status

| Phase | Status |
|-------|--------|
| 1. Foundation | Complete |
| 2. Protocol Layer | Complete |
| 3. Authentication | Complete |
| 4. Realm Server | Complete |
| 5. Character Management | Complete |
| 6. Core Gameplay | Complete |
| 7. Game Systems | Complete |
| 8. Tradeskills | Complete |
| 9. Public Events | Complete |
| 10. Dungeons & Instances | Complete |
| 11. PvP | In Progress |

See [STATUS.md](docs/STATUS.md) for detailed implementation status.

## License

This project is for educational purposes. WildStar is a trademark of NCSOFT Corporation.
