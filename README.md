# Bezgelor

A WildStar MMORPG server emulator written in Elixir, ported from [NexusForever](https://github.com/NexusForever/NexusForever) (C#).

## Overview

Bezgelor is an Elixir umbrella application that emulates WildStar game servers using OTP for concurrency and fault tolerance. The project implements the full server stack including authentication, realm selection, and world gameplay. A Phoenix LiveView account portal provides players with a web dashboard for managing characters, inventory, and guilds, while administrators get a real-time console for server monitoring, user management, and event control. The project also includes tools such as a packet capture system enabling efficient reverse engineering of unknown protocol packets.

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
- **Account Portal** - Web-based player dashboard and admin console with real-time server management

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
| `bezgelor_portal` | Phoenix LiveView account portal - player dashboard & admin console |
| `bezgelor_dev` | Development capture system for reverse engineering |

### Key Patterns

- **Contexts** - Domain modules (`BezgelorDb.Accounts`, `BezgelorDb.Characters`, etc.) provide the public API
- **Packets** - Implement `Readable`/`Writable` behaviours for binary protocol parsing
- **Handlers** - Process incoming packets and dispatch responses
- **Zone Instances** - GenServers managing entities, spawns, and broadcasts per zone
- **Supervision Trees** - OTP supervision for fault tolerance

## Requirements

- Elixir 1.15+
- PostgreSQL 14+ (configured on port 5433)
- Docker & Docker Compose (for database)
- WildStar game client data files

## Quick Start

```bash
# First time setup
./scripts/setup.sh

# Start all servers
./scripts/start.sh
```

That's it! The portal is at **http://localhost:4001** and all game servers are running.

## Running the Server

### Services Overview

When you start the server, the following services come online:

| Service | Port | Description |
|---------|------|-------------|
| Portal (Website) | 4001 | Player dashboard & admin console |
| Auth Server (STS) | 6600 | Client authentication |
| Realm Server | 23115 | Character selection |
| World Server | 24000 | Game world |
| PostgreSQL | 5433 | Database (via Docker) |

### Scripts

| Script | Description |
|--------|-------------|
| `./scripts/setup.sh` | First-time setup: database + deps + migrations |
| `./scripts/start.sh` | Start all servers (interactive) |
| `./scripts/start-bg.sh` | Start all servers in background |
| `./scripts/stop.sh` | Stop all services |
| `./scripts/reset-db.sh` | Reset database (drop + create + migrate + seed) |
| `./scripts/db-up.sh` | Start just the database |

### Manual Start Commands

```bash
# Full stack with live reload (recommended for development)
iex -S mix phx.server

# Full stack without interactive shell
mix phx.server

# Servers only (no portal live reload)
mix run --no-halt

# With named node (for distributed/clustering)
iex --sname bezgelor -S mix phx.server
```

### Database Management

```bash
# Start PostgreSQL container
docker compose up -d

# Stop PostgreSQL container
docker compose down

# View container status
docker compose ps

# First-time setup (create, migrate, seed)
mix ecto.setup

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Run pending migrations only
mix ecto.migrate

# Rollback last migration
mix ecto.rollback
```

### Verifying Services

In the IEx shell, you can verify all applications are running:

```elixir
# List all started applications
Application.started_applications()

# Check specific servers are listening
:gen_tcp.connect(~c"localhost", 6600, [])   # Auth
:gen_tcp.connect(~c"localhost", 23115, [])  # Realm
:gen_tcp.connect(~c"localhost", 24000, [])  # World
```

### Connecting a Game Client

1. Configure your WildStar client's `ClientConfig.ini`:
   ```ini
   [Network]
   Server = localhost
   Port = 6600
   ```

2. Create an account at http://localhost:4001/register

3. Launch `WildStar64.exe` and log in

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_DB` | bezgelor_dev | Database name |
| `POSTGRES_USER` | bezgelor | Database user |
| `POSTGRES_PASSWORD` | bezgelor_dev | Database password |
| `POSTGRES_HOST` | localhost | Database host |
| `POSTGRES_PORT` | 5433 | Database port |

### Config Files

- `config/config.exs` - Base configuration
- `config/dev.exs` - Development overrides
- `config/test.exs` - Test environment
- `config/prod.exs` - Production settings
- `config/runtime.exs` - Runtime configuration (env vars)

## Testing

```bash
# Run all tests (excludes database tests)
mix test

# Run tests for a specific app
mix test apps/bezgelor_core/test/

# Include database tests
mix test --include database
```

## Development Capture System

The `bezgelor_dev` app provides zero-overhead infrastructure for reverse engineering unknown WildStar protocol packets. When enabled in development mode:

1. Unknown/unhandled packets are automatically captured with rich context
2. An interactive terminal UI prompts for what action triggered the packet
3. Markdown reports and LLM-ready analysis prompts are generated
4. Prompts can be fed to any LLM for offline packet analysis

Enable in `config/dev.exs`:

```elixir
config :bezgelor_dev,
  mode: :interactive,  # :disabled | :logging | :interactive
  capture_directory: "priv/dev_captures"
```

Compile-time macros ensure zero runtime overhead when disabled. See [dev_capture_system.md](docs/dev_capture_system.md) for full documentation.

## Account Portal

The `bezgelor_portal` app provides a full-featured web interface for players and administrators built with Phoenix LiveView.

### Player Dashboard

- **Character Overview** - View all characters with stats, gear, and progression
- **Inventory Browser** - Browse bags, bank, and equipped items
- **Achievement Tracker** - Track progress across all achievement categories
- **Guild Management** - View guild roster, ranks, and manage applications
- **Mail Center** - Read, compose, and manage in-game mail with attachments
- **Settings** - Update email, password, and account preferences

### Admin Console

- **Server Dashboard** - Real-time monitoring of online players, zones, and server health
- **User Management** - Search accounts, view details, suspend/ban, reset passwords
- **Character Tools** - Grant items/currency, modify stats, teleport, reset lockouts
- **Economy Monitor** - Track currency distribution, transaction history, grant rewards
- **Instance Management** - Monitor active dungeons/raids, teleport players, close instances
- **Event Control** - Start/stop public events, spawn world bosses, manage schedules
- **Analytics** - Player activity trends, economy graphs, content completion rates
- **Audit Logs** - Complete history of all admin actions with filtering

### Access Control

Role-based permissions (Player, GM, Admin, SuperAdmin) control access to features. All admin actions are logged with full audit trails.

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
| 11. PvP | Complete |
| 12. Account Portal | Complete |

See [status.md](docs/status.md) for detailed implementation status.

## License

This project is licensed under the [GNU Affero General Public License v3.0](LICENSE). This means if you run a modified version of this server software, you must make your source code available to users who connect to it.

WildStar is a trademark of NCSOFT Corporation. This project is not affiliated with or endorsed by NCSOFT.
