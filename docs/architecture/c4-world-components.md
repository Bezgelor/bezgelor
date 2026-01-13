# C4 Component Diagram - World Server

This diagram shows the internal components of the World Server (bezgelor_world), the most complex container.

```mermaid
C4Component
    title Component Diagram - World Server (bezgelor_world)

    Container_Ext(client, "WildStar Client", "Game client")
    Container_Ext(protocol, "Protocol Library", "Packet handling")
    Container_Ext(db, "Database Layer", "Ecto contexts")
    Container_Ext(data, "Static Data", "ETS game data")
    Container_Ext(core, "Core Library", "Game logic")

    Container_Boundary(world, "World Server") {
        Component(conn, "Connection Handler", "GenServer", "Per-player connection process handling packets")

        Component(world_mgr, "WorldManager", "Supervisor", "Supervises all world instances and services")
        Component(world_inst, "World.Instance", "GenServer", "Per-world instance managing entities and state")
        Component(zone_mgr, "Zone.Manager", "GenServer", "Per-zone creature spawns and harvest nodes")

        Component(tick, "TickScheduler", "GenServer", "Master game loop timer (200ms ticks)")
        Component(spell, "SpellManager", "GenServer", "Spell casting coordination")
        Component(buff, "BuffManager", "GenServer", "Buff/debuff tracking and expiration")
        Component(corpse, "CorpseManager", "GenServer", "Death and loot management")

        Component(instance, "Instance System", "Supervisor", "Dungeon and raid instances")
        Component(pvp, "PvP Systems", "Supervisor", "Battlegrounds, arenas, warplots")

        Component(session, "SessionData", "Struct", "Player session state")
        Component(handlers, "Packet Handlers", "Modules", "World packet processing")
    }

    Rel(client, conn, "Sends packets", "TCP 24000")
    Rel(conn, handlers, "Routes packets to")
    Rel(handlers, session, "Updates")
    Rel(handlers, world_inst, "Modifies world state")

    Rel(world_mgr, world_inst, "Supervises")
    Rel(world_mgr, tick, "Supervises")
    Rel(world_mgr, instance, "Supervises")
    Rel(world_mgr, pvp, "Supervises")

    Rel(world_inst, zone_mgr, "Manages zones")
    Rel(world_inst, spell, "Delegates casting")
    Rel(world_inst, buff, "Delegates buffs")
    Rel(world_inst, corpse, "Delegates deaths")

    Rel(tick, world_inst, "Triggers updates")
    Rel(tick, spell, "Triggers updates")
    Rel(tick, buff, "Triggers expirations")

    Rel(handlers, db, "Persists data")
    Rel(zone_mgr, data, "Loads spawns")
    Rel(spell, core, "Uses calculations")

    UpdateLayoutConfig($c4ShapeInRow="4", $c4BoundaryInRow="1")
```

## Component Descriptions

### Connection Layer

| Component | Process Type | Responsibility |
|-----------|--------------|----------------|
| **Connection Handler** | GenServer (per player) | Manages player TCP connection, packet I/O |
| **Packet Handlers** | Modules | Process specific packet types (movement, combat, etc.) |
| **SessionData** | Struct | Player session state (position, target, flags) |

### World Management

| Component | Process Type | Responsibility |
|-----------|--------------|----------------|
| **WorldManager** | Supervisor | Top-level supervisor for all world processes |
| **World.Instance** | GenServer (per world) | Manages entities, visibility, state for one world |
| **Zone.Manager** | GenServer (per zone) | Creature spawns, harvest nodes within a zone |

### Game Services

| Component | Process Type | Responsibility |
|-----------|--------------|----------------|
| **TickScheduler** | GenServer | Master game loop (200ms tick), triggers all updates |
| **SpellManager** | GenServer | Coordinates spell casting, cooldowns, effects |
| **BuffManager** | GenServer | Tracks active buffs/debuffs, handles expirations |
| **CorpseManager** | GenServer | Death handling, corpse timers, loot distribution |

### Instanced Content

| Component | Process Type | Responsibility |
|-----------|--------------|----------------|
| **Instance System** | Supervisor | Manages dungeon/raid instances (per group) |
| **PvP Systems** | Supervisor | Battlegrounds, arenas, warplots with queues |

## Process Model

```
Each Player = 1 Connection Process (GenServer)
Each Active World = 1 World.Instance Process (GenServer)
Each Zone within World = 1 Zone.Manager Process (GenServer)
Each Dungeon Group = 1 Instance Process (GenServer)

Communication: Erlang message passing (no shared state)
Fault Tolerance: Supervision trees restart failed processes
```

## Game Loop

```
TickScheduler (200ms interval)
    │
    ├─→ World.Instance.tick()
    │       ├─→ Update entity positions
    │       ├─→ Process visibility changes
    │       └─→ Broadcast state updates
    │
    ├─→ SpellManager.tick()
    │       ├─→ Process casting spells
    │       └─→ Apply spell effects
    │
    └─→ BuffManager.tick()
            └─→ Expire finished buffs
```
