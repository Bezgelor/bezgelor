# BezgelorDb

Ecto-based database layer for persistent game data.

## Features

- Account and character management
- Guild and social systems
- Inventory and item storage
- Quest progress tracking
- Instance lockouts

## Context Modules

- `BezgelorDb.Accounts` - Account CRUD and authentication
- `BezgelorDb.Characters` - Character persistence
- `BezgelorDb.Guilds` - Guild management
- `BezgelorDb.Inventory` - Item and bag management
- `BezgelorDb.Quests` - Quest progress

## Database Setup

```bash
# Create and migrate
mix ecto.create
mix ecto.migrate

# Reset (drops and recreates)
mix ecto.reset
```

PostgreSQL on port 5433 (non-standard). Configure via environment variables.
