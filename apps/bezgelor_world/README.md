# BezgelorWorld

World server managing game state, players, and combat.

## Features

- World instance management (one GenServer per active world)
- Player session handling
- Entity spawning and despawning
- Combat resolution
- Movement and position tracking
- Spell casting and effects
- NPC and creature AI
- TCP listener on port 24000

## Architecture

- Each connected player runs as a supervised process
- World instances are GenServers managing entities within that world
- Communication via message passing (no shared state)
- Fault tolerance through supervision trees

## Key Modules

- `BezgelorWorld.World.Instance` - World instance state management (keyed by world_id, not zone_id)
- `BezgelorWorld.Handler.*` - Packet handlers for world operations
- `BezgelorWorld.Combat` - Combat state machine
- `BezgelorWorld.Movement` - Position and movement validation
