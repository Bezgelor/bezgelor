# Bezgelor Architecture

A comprehensive guide to the Bezgelor server architecture for engineers unfamiliar with Elixir/OTP.

## Table of Contents

1. [Elixir/OTP Primer](#elixirotp-primer)
2. [High-Level Overview](#high-level-overview)
3. [Umbrella Application Structure](#umbrella-application-structure)
4. [Process Model](#process-model)
5. [Supervision Trees](#supervision-trees)
6. [Message Passing](#message-passing)
7. [Packet Flow](#packet-flow)
8. [Data Architecture](#data-architecture)
9. [Player Session Lifecycle](#player-session-lifecycle)
10. [Web Portal Architecture](#web-portal-architecture)
11. [Key Design Patterns](#key-design-patterns)

---

## Elixir/OTP Primer

Before diving into the architecture, here are key Elixir/OTP concepts explained for engineers from other ecosystems:

### Processes (Not OS Processes)

Elixir processes are **lightweight, isolated units of execution** - think goroutines or Erlang actors:

| Concept | Elixir | Java/C# Equivalent |
|---------|--------|-------------------|
| Process | ~2KB memory, millions possible | Thread (~1MB stack) |
| Communication | Message passing only | Shared memory + locks |
| Failure | Isolated, doesn't crash others | Can corrupt shared state |
| State | Each process owns its state | Shared mutable state |

```
┌─────────────────────────────────────────────────────────┐
│                      BEAM VM                            │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │
│  │Process 1│ │Process 2│ │Process 3│ │Process N│  ...   │
│  │  ~2KB   │ │  ~2KB   │ │  ~2KB   │ │  ~2KB   │        │
│  │ mailbox │ │ mailbox │ │ mailbox │ │ mailbox │        │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘        │
│        ↑           ↑           ↑           ↑            │
│        └───────────┴───────────┴───────────┘            │
│                  Message Passing                        │
└─────────────────────────────────────────────────────────┘
```

### GenServer (Generic Server)

A **GenServer** is a process that:
- Maintains state between calls
- Handles synchronous requests (call) and async messages (cast)
- Has lifecycle callbacks (init, handle_call, handle_cast, handle_info, terminate)

Think of it as a **stateful microservice** running in-process:

```
┌──────────────────────────────────────┐
│            GenServer                 │
│  ┌────────────────────────────────┐  │
│  │         State: %{...}          │  │
│  └────────────────────────────────┘  │
│                                      │
│  handle_call(request) → response     │  ← Synchronous (caller waits)
│  handle_cast(message) → :ok          │  ← Asynchronous (fire & forget)
│  handle_info(message) → :ok          │  ← System/arbitrary messages
└──────────────────────────────────────┘
```

### Supervisor

A **Supervisor** is a process that monitors child processes and restarts them on failure:

```
         ┌─────────────┐
         │ Supervisor  │
         │ (monitors)  │
         └──────┬──────┘
        ┌───────┼───────┐
        ↓       ↓       ↓
   ┌────────┐┌────────┐┌────────┐
   │Child 1 ││Child 2 ││Child 3 │
   └────────┘└────────┘└────────┘
        ↓
   (crashes)
        ↓
   ┌────────┐
   │Child 1 │  ← Restarted automatically
   │ (new)  │
   └────────┘
```

**Restart Strategies:**
- `one_for_one`: Only restart the failed child
- `one_for_all`: Restart all children if one fails
- `rest_for_one`: Restart the failed child and all children started after it

### ETS (Erlang Term Storage)

**ETS** is an in-memory key-value store with:
- O(1) lookups
- Lock-free concurrent reads
- Shared across all processes
- Perfect for static/read-heavy data

Think of it as an **in-process Redis** without serialization overhead.

### Registry

A **Registry** maps names to process IDs, enabling:
- Looking up processes by custom keys
- Pub/sub patterns
- Process groups

---

## High-Level Overview

Bezgelor is a WildStar MMORPG server emulator handling authentication, realm selection, and game world simulation.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Game Client                                 │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│  Auth Server  │      │ Realm Server  │      │ World Server  │
│   Port 6600   │      │  Port 23115   │      │  Port 24000   │
│               │      │               │      │               │
│  - SRP6 Auth  │      │ - Token Valid │      │ - Gameplay    │
│  - Game Token │──────│ - Session Key │──────│ - Characters  │
│               │      │ - Realm List  │      │ - Combat/AI   │
└───────────────┘      └───────────────┘      └───────────────┘
        │                       │                       │
        └───────────────────────┴───────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
                    ▼                       ▼
            ┌───────────────┐      ┌───────────────┐
            │  PostgreSQL   │      │  ETS Tables   │
            │  (Persistent) │      │ (Static Data) │
            │               │      │               │
            │ - Accounts    │      │ - Creatures   │
            │ - Characters  │      │ - Spells      │
            │ - Inventory   │      │ - Items       │
            │ - Quests      │      │ - Zones       │
            └───────────────┘      └───────────────┘
```

---

## Umbrella Application Structure

Bezgelor uses an **umbrella application** - a monorepo pattern where multiple apps share dependencies but have clear boundaries:

```
bezgelor/
├── apps/
│   ├── bezgelor_core/      # Shared game logic (pure functions)
│   ├── bezgelor_crypto/    # Encryption & authentication
│   ├── bezgelor_protocol/  # Network protocol & packet handling
│   ├── bezgelor_db/        # Database schemas & queries
│   ├── bezgelor_data/      # Static game data (ETS)
│   ├── bezgelor_auth/      # Auth server (port 6600)
│   ├── bezgelor_realm/     # Realm server (port 23115)
│   ├── bezgelor_world/     # World server (port 24000)
│   ├── bezgelor_api/       # REST API (port 4002)
│   └── bezgelor_portal/    # Web portal (port 4000)
├── config/                 # Shared configuration
└── mix.exs                 # Umbrella project definition
```

### Dependency Graph

```
                    ┌──────────────────┐
                    │  bezgelor_core   │
                    │  (pure logic)    │
                    └────────┬─────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ bezgelor_crypto │ │  bezgelor_db    │ │ bezgelor_data   │
│ (encryption)    │ │  (PostgreSQL)   │ │ (ETS tables)    │
└────────┬────────┘ └────────┬────────┘ └────────┬────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │ bezgelor_protocol   │
                  │ (packets, framing)  │
                  └──────────┬──────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ bezgelor_auth   │ │ bezgelor_realm  │ │ bezgelor_world  │
│ (STS server)    │ │ (realm server)  │ │ (game server)   │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

### App Responsibilities

| App | Purpose | Key Modules |
|-----|---------|-------------|
| **bezgelor_core** | Pure game logic - no side effects | Entity, Vector3, Spell, Combat, XP, AI |
| **bezgelor_crypto** | Security primitives | SRP6, PacketCrypt, Password |
| **bezgelor_protocol** | Binary protocol | Packets, Framing, Connection, TcpListener |
| **bezgelor_db** | Persistence layer | Repo, Schemas, Context modules |
| **bezgelor_data** | Static game data | Store (ETS), Compiler |
| **bezgelor_auth** | Authentication | Sts.Connection, SRP6 handlers |
| **bezgelor_realm** | Realm management | Session key generation |
| **bezgelor_world** | Game simulation | WorldManager, World.Instance, Handlers |

---

## Process Model

### One Process Per Connection

Each connected client gets a dedicated **Connection process**:

```
┌─────────────────────────────────────────────────────────────────┐
│                        World Server                             │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ Connection  │  │ Connection  │  │ Connection  │    ...       │
│  │  Player 1   │  │  Player 2   │  │  Player 3   │              │
│  │             │  │             │  │             │              │
│  │ - Socket    │  │ - Socket    │  │ - Socket    │              │
│  │ - Encrypt   │  │ - Encrypt   │  │ - Encrypt   │              │
│  │ - Session   │  │ - Session   │  │ - Session   │              │
│  │ - Entity    │  │ - Entity    │  │ - Entity    │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│         │                │                │                     │
│         └────────────────┴────────────────┘                     │
│                          │                                      │
│                          ▼                                      │
│                  ┌───────────────┐                              │
│                  │ WorldManager  │  ← Central session registry  │
│                  │               │                              │
│                  │ - Sessions    │                              │
│                  │ - GUID gen    │                              │
│                  │ - Chat route  │                              │
│                  └───────────────┘                              │
└─────────────────────────────────────────────────────────────────┘
```

**Benefits:**
- **Isolation**: One player's crash doesn't affect others
- **Concurrency**: Each connection processes packets independently
- **Simplicity**: No locks, no shared mutable state
- **Scalability**: Processes spread across CPU cores automatically

### One Process Per World Instance

Each active world shard runs as its own **World.Instance process**:

```
┌─────────────────────────────────────────────────────────────────┐
│                   World Instance Supervisor                     │
│                    (DynamicSupervisor)                          │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│  │ World.Instance   │  │ World.Instance   │  │ World.Instance │ │
│  │ Thayd (1,1)      │  │ Illium (2,1)     │  │ Dungeon (3,5)  │ │
│  │                  │  │                  │  │                │ │
│  │ Entities: 150    │  │ Entities: 89     │  │ Entities: 12   │ │
│  │ Players: 45      │  │ Players: 23      │  │ Players: 5     │ │
│  │ Creatures: 105   │  │ Creatures: 66    │  │ Creatures: 7   │ │
│  └──────────────────┘  └──────────────────┘  └────────────────┘ │
│                                                                 │
│  Registry: {world_id, instance_id} → pid                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Supervision Trees

### World Server Supervision Hierarchy

```
BezgelorWorld.Supervisor (one_for_one)
│
├── RealmMonitor (GenServer)
│   └── Marks realm online, monitors health
│
├── WorldManager (GenServer)
│   └── Central registry for all player sessions
│
├── TickScheduler (GenServer)
│   └── Master periodic game tick (buffs, AI, etc.)
│
├── CreatureManager (GenServer)
│   └── Spawns and manages NPC creatures
│
├── HarvestNodeManager (GenServer)
│   └── Manages gathering/harvesting nodes
│
├── BuffManager (GenServer)
│   └── Tracks temporary effects on entities
│
├── SpellManager (GenServer)
│   └── Processes spell casts, cooldowns, cast timers
│
├── CorpseManager (GenServer)
│   └── Manages lootable corpses
│
├── WorldRegistry (Registry)
│   └── Maps {world_id, instance_id} → World.Instance pid
│
├── World.InstanceSupervisor (DynamicSupervisor)
│   ├── World.Instance (Thayd, 1)
│   ├── World.Instance (Illium, 1)
│   └── ... (created on demand)
│
├── Instance.Supervisor (DynamicSupervisor)
│   └── Dungeon/Raid instances
│
├── Instance.Registry (GenServer)
│   └── Tracks active instance processes
│
├── GroupFinder (GenServer)
│   └── Matchmaking queue
│
├── LockoutManager (GenServer)
│   └── Manages instance lockout resets
│
├── MythicManager (GenServer)
│   └── Mythic+ keystones and affixes
│
├── EventScheduler (GenServer)
│   └── Schedules and spawns world events
│
├── PvP Subsystem
│   ├── DuelManager
│   ├── BattlegroundSupervisor + Queue
│   ├── ArenaSupervisor + Queue
│   ├── WarplotManager
│   └── SeasonScheduler
│
└── TcpListener (Ranch)
    └── Spawns Connection processes for each client
```

### Failure Isolation Example

```
                    ┌─────────────────┐
                    │   Supervisor    │
                    │ (one_for_one)   │
                    └────────┬────────┘
           ┌─────────────────┼─────────────────┐
           │                 │                 │
           ▼                 ▼                 ▼
    ┌────────────┐    ┌────────────┐    ┌────────────┐
    │  Player 1  │    │  Player 2  │    │  Player 3  │
    │ Connection │    │ Connection │    │ Connection │
    └────────────┘    └─────┬──────┘    └────────────┘
                            │
                      Player 2 crashes
                      (bad packet, bug)
                            │
                            ▼
                    ┌────────────┐
                    │  Player 2  │  ← Supervisor restarts
                    │ Connection │    (client reconnects)
                    │   (new)    │
                    └────────────┘

    Players 1 & 3 continue unaffected!
```

---

## Message Passing

### Synchronous Call (Request/Response)

```elixir
# Caller blocks until response
result = GenServer.call(WorldManager, {:get_session, account_id})
```

```
┌─────────────┐                      ┌─────────────┐
│  Handler    │                      │WorldManager │
│  Process    │                      │  Process    │
└──────┬──────┘                      └──────┬──────┘
       │                                    │
       │  GenServer.call({:get_session})    │
       │ ─────────────────────────────────► │
       │                                    │
       │         (blocks waiting)           │ handle_call
       │                                    │ looks up session
       │                                    │
       │  {:ok, %{character_name: "Bob"}}   │
       │ ◄───────────────────────────────── │
       │                                    │
       ▼                                    ▼
```

### Asynchronous Cast (Fire & Forget)

```elixir
# Caller continues immediately
GenServer.cast(WorldManager, {:broadcast_chat, message})
```

```
┌─────────────┐                      ┌─────────────┐
│  Handler    │                      │WorldManager │
│  Process    │                      │  Process    │
└──────┬──────┘                      └──────┬──────┘
       │                                    │
       │  GenServer.cast({:broadcast})      │
       │ ─────────────────────────────────► │
       │                                    │
       │  (continues immediately)           │ handle_cast
       │                                    │ sends to all
       ▼                                    │
                                            ▼
```

### Direct Send (For Broadcasts)

```elixir
# Send directly to a process
send(connection_pid, {:send_packet, :server_chat, payload})
```

```
┌─────────────┐                      ┌─────────────┐
│WorldManager │                      │ Connection  │
│  Process    │                      │  Process    │
└──────┬──────┘                      └──────┬──────┘
       │                                    │
       │  send({:send_packet, ...})         │
       │ ─────────────────────────────────► │
       │                                    │ handle_info
       │  send({:send_packet, ...})         │ encrypts & sends
       │ ─────────────────────────────────► │
       │                                    │
       ▼                                    ▼
  (to next player)
```

### Chat Broadcast Flow

```
┌──────────────────────────────────────────────────────────────────┐
│ Player sends: "Hello everyone!"                                  │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ Connection Process (Player 1)                                    │
│ └── ChatHandler.handle(packet, state)                            │
│     └── WorldManager.broadcast_chat(:say, message, position)     │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│ WorldManager Process                                             │
│ └── handle_cast({:broadcast_chat, ...})                          │
│     └── For each session in same zone:                           │
│         └── send(session.connection_pid, {:send_chat, ...})      │
└──────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
│ Connection (P2)   │ │ Connection (P3)   │ │ Connection (P4)   │
│ handle_info       │ │ handle_info       │ │ handle_info       │
│ {:send_chat}      │ │ {:send_chat}      │ │ {:send_chat}      │
│ └── encrypt       │ │ └── encrypt       │ │ └── encrypt       │
│ └── socket.send   │ │ └── socket.send   │ │ └── socket.send   │
└───────────────────┘ └───────────────────┘ └───────────────────┘
```

---

## Packet Flow

### End-to-End Packet Processing

```
┌─────────────────────────────────────────────────────────────────────┐
│                          GAME CLIENT                                │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ Player types "/say Hello!" → ClientChat packet              │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────┬───────────────────────────────┘
                                      │ TCP
                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 1. TCP RECEIVE                                                      │
│    Connection.handle_info({:tcp, socket, raw_bytes})                │
│    └── Accumulate in buffer                                         │
└─────────────────────────────────────┬───────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 2. FRAMING                                                          │
│    Framing.parse_packets(buffer)                                    │
│    └── Extract: [{opcode: 0x03DC, payload: <<...>>}, ...]           │
│    └── Return remaining buffer for next read                        │
└─────────────────────────────────────┬───────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 3. DECRYPTION (if encrypted)                                        │
│    PacketCrypt.decrypt(encryption_state, payload)                   │
│    └── Returns: {decrypted_payload, new_encryption_state}           │
└─────────────────────────────────────┬───────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 4. OPCODE LOOKUP                                                    │
│    Opcode.from_integer(0x07B0) → {:ok, :client_chat}                │
└─────────────────────────────────────┬───────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 5. HANDLER DISPATCH                                                 │
│    PacketRegistry.lookup(:client_chat)                              │
│    └── Returns: BezgelorWorld.Handler.ChatHandler                   │
│                                                                     │
│    ChatHandler.handle(payload, connection_state)                    │
│    └── Parse: ClientChat.read(payload) → %ClientChat{message: ...}  │
│    └── Validate: Middleware.require_in_world()                      │
│    └── Process: WorldManager.broadcast_chat(...)                    │
│    └── Return: {:ok, new_state}                                     │
└─────────────────────────────────────┬───────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│ 6. RESPONSE PACKETS (to other players)                              │
│    For each recipient connection:                                   │
│    └── ServerChat.write(%ServerChat{...})                           │
│    └── PacketCrypt.encrypt(payload)                                 │
│    └── Frame with opcode 0x03DC                                     │
│    └── socket.send(framed_packet)                                   │
└─────────────────────────────────────────────────────────────────────┘
```

### Handler Registration (Breaking Circular Dependencies)

The protocol layer needs to dispatch to world handlers, but the world layer depends on protocol. This is solved with **runtime registration**:

```
┌─────────────────────────────────────────────────────────────────────┐
│ COMPILE TIME                                                        │
│                                                                     │
│   bezgelor_protocol                    bezgelor_world               │
│   ┌─────────────────┐                  ┌─────────────────┐          │
│   │ PacketRegistry  │                  │ ChatHandler     │          │
│   │ (empty map)     │                  │ SpellHandler    │          │
│   │                 │                  │ CombatHandler   │          │
│   │ No dependency   │ ──────────────── │ (26 handlers)   │          │
│   │ on handlers!    │                  │                 │          │
│   └─────────────────┘                  └─────────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Application starts
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ RUNTIME (BezgelorWorld.Application.start)                           │
│                                                                     │
│   # Register handlers BEFORE supervision tree                       │
│   HandlerRegistration.register_all()                                │
│   │                                                                 │
│   └── PacketRegistry.register(:client_chat, ChatHandler)            │
│   └── PacketRegistry.register(:client_cast_spell, SpellHandler)     │
│   └── PacketRegistry.register(:client_movement, MovementHandler)    │
│   └── ... (26 total)                                                │
│                                                                     │
│   # NOW start supervision tree (including TCP listener)             │
│   Supervisor.start_link(children, opts)                             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Data Architecture

### Two Data Stores

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA ARCHITECTURE                             │
├─────────────────────────────────┬───────────────────────────────────┤
│         POSTGRESQL              │              ETS                   │
│       (bezgelor_db)             │         (bezgelor_data)            │
├─────────────────────────────────┼───────────────────────────────────┤
│                                 │                                    │
│  MUTABLE / PERSISTENT           │  IMMUTABLE / STATIC                │
│                                 │                                    │
│  • Accounts                     │  • Creature definitions            │
│  • Characters                   │  • Spell data                      │
│  • Inventory items              │  • Item templates                  │
│  • Quest progress               │  • Zone definitions                │
│  • Guild membership             │  • Loot tables                     │
│  • Achievement progress         │  • XP curves                       │
│  • Mail                         │  • Spawn locations                 │
│                                 │                                    │
│  Access: Ecto queries           │  Access: O(1) ETS lookup           │
│  Latency: ~1-5ms                │  Latency: ~1-10μs                  │
│                                 │                                    │
└─────────────────────────────────┴───────────────────────────────────┘
```

### ETS Table Loading

```
┌─────────────────────────────────────────────────────────────────────┐
│ APPLICATION STARTUP                                                 │
│                                                                     │
│   priv/data/creatures.json ─────┐                                   │
│   priv/data/spells.json    ─────┤                                   │
│   priv/data/items.json     ─────┼──► BezgelorData.Store.init()      │
│   priv/data/zones.json     ─────┤    │                              │
│   priv/data/quests.json    ─────┘    │                              │
│                                      ▼                              │
│                              ┌─────────────────┐                    │
│                              │   ETS Tables    │                    │
│                              │                 │                    │
│                              │  :creatures     │                    │
│                              │  :spells        │                    │
│                              │  :items         │                    │
│                              │  :zones         │                    │
│                              │  :quests        │                    │
│                              │  ... (66 total) │                    │
│                              └─────────────────┘                    │
│                                      │                              │
│   Any process can read:              │                              │
│   BezgelorData.get_creature(1234) ───┘                              │
│   └── :ets.lookup(:creatures, 1234)                                 │
│   └── Returns in ~1μs                                               │
└─────────────────────────────────────────────────────────────────────┘
```

### Database Context Pattern

```
┌─────────────────────────────────────────────────────────────────────┐
│ CONTEXT PATTERN (Domain-Driven Design)                              │
│                                                                     │
│   Handler Layer          Context Layer           Schema Layer       │
│   (bezgelor_world)       (bezgelor_db)           (bezgelor_db)      │
│                                                                     │
│   ┌─────────────┐       ┌─────────────┐        ┌─────────────┐      │
│   │ ChatHandler │       │             │        │             │      │
│   │             │       │  Accounts   │        │   Account   │      │
│   │ Character   │       │  .get()     │───────►│   Schema    │      │
│   │ SelectHdlr  │──────►│  .create()  │        │             │      │
│   │             │       │  .update()  │        └─────────────┘      │
│   │ QuestHandler│       │             │                             │
│   └─────────────┘       └─────────────┘        ┌─────────────┐      │
│                                                │             │      │
│                         ┌─────────────┐        │  Character  │      │
│                         │             │        │   Schema    │      │
│                         │ Characters  │───────►│             │      │
│                         │ .list()     │        └─────────────┘      │
│                         │ .create()   │                             │
│                         │ .delete()   │        ┌─────────────┐      │
│                         └─────────────┘        │             │      │
│                                                │    Item     │      │
│                         ┌─────────────┐        │   Schema    │      │
│                         │             │───────►│             │      │
│                         │  Inventory  │        └─────────────┘      │
│                         │ .add_item() │                             │
│                         │ .remove()   │                             │
│                         └─────────────┘                             │
│                                                                     │
│   RULE: Handlers NEVER call Repo directly                           │
│         Always go through Context modules                           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Player Session Lifecycle

### Complete Login Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 1: AUTHENTICATION (Port 6600)                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Client                           Auth Server                      │
│      │                                 │                            │
│      │  TCP Connect                    │                            │
│      │ ──────────────────────────────► │                            │
│      │                                 │ Spawn Sts.Connection       │
│      │                                 │                            │
│      │  ClientHelloAuth (SRP6 init)    │                            │
│      │ ──────────────────────────────► │                            │
│      │                                 │                            │
│      │  ServerAuthChallenge            │                            │
│      │ ◄────────────────────────────── │                            │
│      │                                 │                            │
│      │  ClientAuthResponse             │                            │
│      │ ──────────────────────────────► │ Verify credentials         │
│      │                                 │                            │
│      │  ServerAuthComplete + Token     │                            │
│      │ ◄────────────────────────────── │                            │
│      │                                 │                            │
│      │  Disconnect                     │                            │
│      │ ──────────────────────────────► │                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 2: REALM SELECTION (Port 23115)                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Client                           Realm Server                     │
│      │                                 │                            │
│      │  TCP Connect                    │                            │
│      │ ──────────────────────────────► │                            │
│      │                                 │ Spawn Connection           │
│      │                                 │                            │
│      │  ClientHelloAuthRealm + Token   │                            │
│      │ ──────────────────────────────► │ Validate token             │
│      │                                 │ Generate session_key       │
│      │                                 │ Store in database          │
│      │                                 │                            │
│      │  ServerRealmInfo                │                            │
│      │ ◄────────────────────────────── │                            │
│      │                                 │                            │
│      │  ClientRealmList                │                            │
│      │ ──────────────────────────────► │                            │
│      │                                 │                            │
│      │  ServerRealmList                │                            │
│      │ ◄────────────────────────────── │                            │
│      │                                 │                            │
│      │  ClientRealmSelect              │                            │
│      │ ──────────────────────────────► │                            │
│      │                                 │                            │
│      │  ServerRealmSelected            │                            │
│      │ ◄────────────────────────────── │ Includes world server addr │
│      │                                 │                            │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 3: WORLD ENTRY (Port 24000)                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   Client                           World Server                     │
│      │                                 │                            │
│      │  TCP Connect                    │                            │
│      │ ──────────────────────────────► │                            │
│      │                                 │ Spawn Connection           │
│      │                                 │                            │
│      │  ClientHelloRealm + SessionKey  │                            │
│      │ ──────────────────────────────► │ Validate session_key       │
│      │                                 │ Store account_id in state  │
│      │                                 │                            │
│      │  ServerAuthEncrypted (enable)   │                            │
│      │ ◄────────────────────────────── │ Encryption now active      │
│      │                                 │                            │
│      │  ClientCharacterList            │                            │
│      │ ──────────────────────────────► │                            │
│      │                                 │ Query: Characters.list()   │
│      │                                 │                            │
│      │  ServerCharacterList            │                            │
│      │ ◄────────────────────────────── │                            │
│      │                                 │                            │
│      │  ClientCharacterSelect          │                            │
│      │ ──────────────────────────────► │                            │
│      │                                 │ Load character             │
│      │                                 │ Generate entity GUID       │
│      │                                 │ Register session           │
│      │                                 │                            │
│      │  ServerWorldEnter               │                            │
│      │ ◄────────────────────────────── │                            │
│      │                                 │                            │
│      │  ServerEntityCreate (self)      │                            │
│      │ ◄────────────────────────────── │                            │
│      │                                 │                            │
│      │  (Loading screen...)            │                            │
│      │                                 │                            │
│      │  ClientEnteredWorld             │                            │
│      │ ──────────────────────────────► │                            │
│      │                                 │ Set in_world = true        │
│      │                                 │ Add to World.Instance      │
│      │                                 │ Start quest timer          │
│      │                                 │                            │
│      │  ServerEntityCreate (others)    │                            │
│      │ ◄────────────────────────────── │ Nearby players/creatures   │
│      │                                 │                            │
│      ▼                                 ▼                            │
│                  PLAYING THE GAME                                   │
└─────────────────────────────────────────────────────────────────────┘
```

### Session State

```
┌─────────────────────────────────────────────────────────────────────┐
│ CONNECTION PROCESS STATE                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  %Connection{                                                       │
│    socket: #Port<0.1234>,          # TCP socket                     │
│    transport: :ranch_tcp,          # Transport module               │
│    connection_type: :world,        # :auth | :realm | :world        │
│    buffer: <<...>>,                # Incomplete packet data         │
│    encryption: %PacketCrypt{...},  # Encryption state               │
│    state: :authenticated,          # Connection state               │
│                                                                     │
│    session_data: %{                # Player session                 │
│      account_id: 12345,                                             │
│      character_id: 67890,                                           │
│      character_name: "PlayerOne",                                   │
│      entity_guid: 0x2000_0000_0001_0935,                            │
│      entity: %Entity{...},         # Current entity state           │
│      in_world: true,                                                │
│      zone_id: 426,                 # Current zone                   │
│      instance_id: 1,                                                │
│      in_combat: false,                                              │
│                                                                     │
│      # Quest system                                                 │
│      active_quests: %{quest_id => progress},                        │
│      completed_quest_ids: MapSet<[...]>,                            │
│      quest_dirty: false,           # Needs persistence              │
│                                                                     │
│      # Achievement tracking                                         │
│      achievement_handler: #PID<0.456.0>                             │
│    }                                                                │
│  }                                                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Web Portal Architecture

The **bezgelor_portal** application provides a web interface for players and administrators, separate from the game client flow.

### Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Web Browser                                  │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ HTTP/WebSocket
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    bezgelor_portal (Port 4000)                       │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                     Phoenix LiveView                         │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │    │
│  │  │   Public    │  │    User     │  │       Admin         │  │    │
│  │  │   Pages     │  │  Dashboard  │  │       Panel         │  │    │
│  │  │             │  │             │  │                     │  │    │
│  │  │ - Home      │  │ - Characters│  │ - User Management   │  │    │
│  │  │ - Features  │  │ - Settings  │  │ - Character Admin   │  │    │
│  │  │ - Download  │  │ - TOTP      │  │ - Server Settings   │  │    │
│  │  │ - Login     │  │             │  │ - Audit Logs        │  │    │
│  │  │ - Register  │  │             │  │ - Economy/Events    │  │    │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                │                                     │
│                                ▼                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    BezgelorWorld.Portal                      │    │
│  │                   (World Server Bridge)                      │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                │                                     │
└────────────────────────────────┼────────────────────────────────────┘
                                 │ GenServer calls
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    bezgelor_world (Port 24000)                       │
│                                                                      │
│  WorldManager, CreatureManager, World.Instance, BuffManager, etc.   │
└─────────────────────────────────────────────────────────────────────┘
```

### Authentication Flow

Portal authentication is separate from game client SRP6 authentication:

```
┌─────────────────────────────────────────────────────────────────────┐
│ PORTAL LOGIN FLOW                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Browser                          Portal                            │
│      │                               │                               │
│      │  GET /login                   │                               │
│      │ ────────────────────────────► │                               │
│      │                               │                               │
│      │  LoginLive (LiveView)         │                               │
│      │ ◄──────────────────────────── │                               │
│      │                               │                               │
│      │  Submit email/password        │                               │
│      │ ────────────────────────────► │                               │
│      │                               │ Accounts.authenticate()       │
│      │                               │ └── Argon2 password verify    │
│      │                               │                               │
│      │  (If TOTP enabled)            │                               │
│      │  Redirect to /auth/totp-verify│                               │
│      │ ◄──────────────────────────── │                               │
│      │                               │                               │
│      │  Submit TOTP code             │                               │
│      │ ────────────────────────────► │                               │
│      │                               │ NimbleTOTP.valid?()           │
│      │                               │                               │
│      │  Set session cookie           │                               │
│      │  Redirect to /dashboard       │                               │
│      │ ◄──────────────────────────── │                               │
│      │                               │                               │
└─────────────────────────────────────────────────────────────────────┘
```

### LiveView Architecture

Portal uses Phoenix LiveView for real-time, stateful UI without JavaScript:

```
┌─────────────────────────────────────────────────────────────────────┐
│ LIVEVIEW STRUCTURE                                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Router (router.ex)                                                 │
│   │                                                                  │
│   ├── live_session :auth (layout: :auth)                            │
│   │   ├── /login         → LoginLive                                │
│   │   ├── /register      → RegisterLive                             │
│   │   └── /auth/totp-verify → TotpVerifyLive                        │
│   │                                                                  │
│   ├── live_session :authenticated (on_mount: require_auth)          │
│   │   ├── /dashboard     → DashboardLive                            │
│   │   ├── /characters    → CharactersLive                           │
│   │   ├── /characters/:id → CharacterDetailLive                     │
│   │   └── /settings      → SettingsLive                             │
│   │                                                                  │
│   └── live_session :admin (on_mount: require_admin)                 │
│       ├── /admin         → AdminDashboardLive                       │
│       ├── /admin/users   → Admin.UsersLive                          │
│       ├── /admin/characters → Admin.CharactersLive                  │
│       ├── /admin/settings → Admin.SettingsLive                      │
│       ├── /admin/roles   → Admin.RolesLive                          │
│       └── /admin/audit-log → Admin.AuditLogLive                     │
│                                                                      │
│   Layouts (layouts.ex)                                               │
│   │                                                                  │
│   ├── :gaming  → Public pages (animated background, gaming style)   │
│   ├── :auth    → Login/register pages (minimal, centered card)      │
│   ├── :app     → Authenticated user pages (navbar, footer)          │
│   └── :admin   → Admin panel (navbar + sidebar navigation)          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Role-Based Access Control (RBAC)

The admin panel uses a permission-based authorization system:

```
┌─────────────────────────────────────────────────────────────────────┐
│ RBAC HIERARCHY                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Account                                                            │
│      │                                                               │
│      │ has many                                                      │
│      ▼                                                               │
│   AccountRole (join table)                                           │
│      │                                                               │
│      │ belongs to                                                    │
│      ▼                                                               │
│   Role (e.g., "Game Master", "Moderator", "Admin")                  │
│      │                                                               │
│      │ has many                                                      │
│      ▼                                                               │
│   RolePermission (join table)                                        │
│      │                                                               │
│      │ belongs to                                                    │
│      ▼                                                               │
│   Permission (e.g., "users.view", "characters.modify_items")        │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│ PERMISSION CATEGORIES                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   user_management      │ users.view, users.ban, users.reset_password│
│   character_management │ characters.view, characters.modify_items   │
│   economy              │ economy.grant_currency, economy.view_stats │
│   events               │ events.manage, events.broadcast_message    │
│   server               │ server.settings, server.view_logs          │
│   administration       │ admin.manage_roles, admin.view_audit_log   │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│ AUTHORIZATION CHECK                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   # In LiveView mount                                                │
│   def mount(_params, _session, socket) do                           │
│     account = socket.assigns.current_account                        │
│     permissions = Authorization.list_permissions(account)           │
│                                                                      │
│     unless "users.view" in permissions do                           │
│       {:ok, redirect(socket, to: "/admin")}                         │
│     else                                                             │
│       {:ok, assign(socket, permissions: permissions)}               │
│     end                                                              │
│   end                                                                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Portal ↔ World Server Bridge

The `BezgelorWorld.Portal` module bridges the portal with the running world server:

```
┌─────────────────────────────────────────────────────────────────────┐
│ PORTAL MODULE API                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   BezgelorWorld.Portal                                               │
│   │                                                                  │
│   ├── Player Management                                              │
│   │   ├── list_online_players()     → [%{account_id, char_name}]    │
│   │   ├── online_player_count()     → integer                       │
│   │   ├── kick_player(account_id)   → :ok | {:error, :not_online}   │
│   │   └── players_by_zone()         → %{zone_id => count}           │
│   │                                                                  │
│   ├── Zone Management                                                │
│   │   ├── list_active_zones()       → [%{zone_id, player_count}]    │
│   │   └── get_zone_info(zone_id)    → %{name, players, creatures}   │
│   │                                                                  │
│   ├── Broadcasting                                                   │
│   │   └── broadcast_system_message(text) → :ok                      │
│   │                                                                  │
│   ├── Server Configuration                                           │
│   │   ├── get_all_settings()        → %{section => settings}        │
│   │   ├── update_setting(s, k, v)   → :ok | {:error, reason}        │
│   │   └── restart_world_server(delay) → {:ok, %{players_affected}}  │
│   │                                                                  │
│   └── Server Status                                                  │
│       └── world_server_running?()   → boolean                       │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│ HOW IT WORKS                                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Portal LiveView         Portal Module           WorldManager       │
│        │                       │                       │             │
│        │  Admin clicks         │                       │             │
│        │  "Kick Player"        │                       │             │
│        │ ─────────────────────►│                       │             │
│        │                       │                       │             │
│        │           Portal.kick_player(account_id)      │             │
│        │                       │ ─────────────────────►│             │
│        │                       │                       │             │
│        │                       │  get_session()        │             │
│        │                       │  send(pid, disconnect)│             │
│        │                       │                       │             │
│        │                       │  :ok                  │             │
│        │                       │ ◄─────────────────────│             │
│        │                       │                       │             │
│        │  {:noreply, socket    │                       │             │
│        │   |> put_flash(:info)}│                       │             │
│        │ ◄─────────────────────│                       │             │
│        │                       │                       │             │
└─────────────────────────────────────────────────────────────────────┘
```

### Audit Logging

All admin actions are logged for accountability:

```
┌─────────────────────────────────────────────────────────────────────┐
│ AUDIT LOG FLOW                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Admin Action                                                       │
│        │                                                             │
│        ▼                                                             │
│   Authorization.log_action(                                          │
│     admin_account,                                                   │
│     "users.ban",              # action                               │
│     "account",                # resource_type                        │
│     target_account_id,        # resource_id                          │
│     %{reason: "...", duration: 24}  # metadata                       │
│   )                                                                  │
│        │                                                             │
│        ▼                                                             │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │ admin_audit_log table                                        │   │
│   │                                                              │   │
│   │ id │ admin_id │ action     │ resource │ metadata │ timestamp│   │
│   │ ───┼──────────┼────────────┼──────────┼──────────┼──────────│   │
│   │ 1  │ 5        │ users.ban  │ account:7│ {reason} │ 2025-... │   │
│   │ 2  │ 5        │ server.set │ config   │ {key,val}│ 2025-... │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Server Configuration System

Runtime-configurable settings with persistence:

```
┌─────────────────────────────────────────────────────────────────────┐
│ SERVER CONFIG ARCHITECTURE                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   Admin UI (SettingsLive)                                            │
│        │                                                             │
│        │  update_setting(:gameplay, :unlock_all_specs, true)        │
│        ▼                                                             │
│   BezgelorWorld.Portal                                               │
│        │                                                             │
│        ▼                                                             │
│   BezgelorWorld.ServerConfig                                         │
│        │                                                             │
│        ├── validate_setting(module, key, value)                     │
│        │   └── Check type, constraints from schema                  │
│        │                                                             │
│        ├── apply_setting(section, key, value)                       │
│        │   └── Application.put_env(:bezgelor_world, :gameplay, ...) │
│        │                                                             │
│        └── persist_config()                                          │
│            └── Write to priv/config/server_config.json              │
│                                                                      │
├─────────────────────────────────────────────────────────────────────┤
│ CONFIG MODULE PATTERN                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   # Each config section defines a schema                             │
│   defmodule BezgelorWorld.GameplayConfig do                         │
│     def schema do                                                    │
│       %{                                                             │
│         unlock_all_specs: %{                                         │
│           type: :boolean,                                            │
│           description: "Unlock all 4 specs for new characters",     │
│           impact: :new_characters_only,                              │
│           default: true                                              │
│         },                                                           │
│         default_tier_points: %{                                      │
│           type: :integer,                                            │
│           description: "Starting tier points",                       │
│           impact: :new_characters_only,                              │
│           constraints: %{min: 0, max: 42},                          │
│           default: 42                                                │
│         }                                                            │
│       }                                                              │
│     end                                                              │
│   end                                                                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Key Design Patterns

### 1. Process Per Connection

Each player connection is an isolated process. Benefits:
- Crash isolation
- No locking
- Natural concurrency
- Clean state management

### 2. Central Registry (WorldManager)

Single source of truth for active sessions:
- O(1) lookup by account, name, or GUID
- Maintains zone indexes for broadcasts
- Routes inter-player communication

### 3. Handler Middleware

Composable validation pipeline:
```
Middleware.run(state, [
  Middleware.log_entry("SpellHandler"),
  &Middleware.require_in_world/1,
  &Middleware.extract_entity/1,
  &Middleware.require_alive/1,
  &Middleware.require_not_in_combat/1
], fn context ->
  # Guaranteed: in_world, alive, not in combat
  cast_spell(context)
end)
```

### 4. ETS for Static Data

All immutable game data in ETS:
- Zero database queries for lookups
- Lock-free concurrent reads
- Microsecond latency

### 5. Context Pattern

Database access through domain modules:
- `Characters.create(attrs)` not `Repo.insert(changeset)`
- Business logic in contexts
- Handlers stay thin

### 6. Dynamic Supervisors

World instances created on demand:
- `DynamicSupervisor.start_child(WorldInstanceSupervisor, {World.Instance, opts})`
- Automatic cleanup when empty
- Fault tolerance per zone

### 7. Registry for Named Lookups

```elixir
# Register world instance
{:via, Registry, {WorldRegistry, {world_id, instance_id}}}

# Call by name tuple
World.Instance.add_entity({426, 1}, entity)
```

---

## Summary

Bezgelor's architecture leverages Elixir/OTP's strengths:

| Challenge               | Solution                            |
|-------------------------|-------------------------------------|
| Many concurrent players | Process per connection |
| Crash isolation         | Supervision trees |
| Shared game state.      | Message passing, no locks |
| Fast static data access | ETS tables |
| Player session tracking | Central registry (WorldManager) |
| Zone management         | Process per zone instance |
| Circular dependencies   | Runtime handler registration |
| Code organization       | Umbrella apps with clear boundaries |

The result is a highly concurrent, fault-tolerant server that can handle thousands of players while remaining maintainable and debuggable.
