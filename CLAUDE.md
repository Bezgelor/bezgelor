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

**Packets (bezgelor_protocol)**: Implement `Readable` and/or `Writable` behaviours. Located in `lib/bezgelor_protocol/packets/{realm,world}/`. Use `PacketReader`/`PacketWriter` for binary parsing. See "Packet Writing (CRITICAL)" section below.

**Handlers (bezgelor_protocol)**: Process incoming packets. Located in `lib/bezgelor_protocol/handler/`. Pattern: receive packet → validate → call context → send response packets.

**World Instances (bezgelor_world)**: GenServers managing entities, spawns, and broadcasts. One process per active world. Note: `world_id` identifies the map/continent, `zone_id` identifies sub-regions within a world.

**Game Logic (bezgelor_core)**: Pure functions for calculations (damage, XP, loot). State management handled by GenServers in bezgelor_world.

### Process Model

- Each connected player is a process
- Each active world is a process
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
NexusForever source is at ../nexusforever/ and database extract at ../NexusForever.WorldDatabase

## Misc. Notes & Requirements
- Architecture, design, and code should be Elixir idiomatic, such as message passing
- Adopt existing implementation patterns, such as the master tick supplier, before implementing basic bespoke services. If that's necessary ask about creating a platform service rather than something specific to functional domain.
- When loading JSON game data files use the ETF caching system via the load_json_raw/1 function

## Packet Writing (CRITICAL)

WildStar uses **continuous bit-packed serialization**. All data is written into a single bit stream WITHOUT byte alignment between fields. This matches NexusForever's `GamePacketWriter` behavior.

### Use Bit-Packed Functions in Packets

Always use these functions when writing packet data:

```elixir
# CORRECT - writes into continuous bit stream
writer
|> PacketWriter.write_u8(value)      # 8 bits
|> PacketWriter.write_u16(value)     # 16 bits
|> PacketWriter.write_u32(value)     # 32 bits
|> PacketWriter.write_u64(value)     # 64 bits
|> PacketWriter.write_i32(value)     # signed 32 bits
|> PacketWriter.write_f32(value)     # 32-bit float
|> PacketWriter.write_bits(val, n)   # arbitrary bits
|> PacketWriter.write_bytes_bits(bin) # raw bytes as bits
|> PacketWriter.flush_bits()         # flush at end
```

### Never Use *_flush Functions in Packets

Functions ending in `_flush` break the bit stream by byte-aligning first:

```elixir
# WRONG - breaks continuous bit stream, corrupts packets
writer
|> PacketWriter.write_uint32_flush(value)  # DON'T USE
|> PacketWriter.write_bytes_flush(bytes)   # DON'T USE
```

The `*_flush` functions are only for packet framing (e.g., `connection.ex`) where byte alignment is explicitly needed.

### Example Packet Implementation

```elixir
@impl true
def write(%__MODULE__{} = packet, writer) do
  writer =
    writer
    |> PacketWriter.write_u32(packet.id)
    |> PacketWriter.write_u64(packet.guid)
    |> PacketWriter.write_f32(packet.x)
    |> PacketWriter.write_bits(packet.flags, 5)
    |> PacketWriter.write_wide_string(packet.name)
    |> PacketWriter.flush_bits()

  {:ok, writer}
end
```

### Why This Matters

Using byte-aligned writes in the middle of a packet corrupts ALL subsequent fields. For example, if you write a 5-bit flag followed by a byte-aligned uint32, the uint32 starts at bit 8 instead of bit 5, shifting all following data.
