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
10. [Key Design Patterns](#key-design-patterns)

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
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐       │
│  │Process 1│ │Process 2│ │Process 3│ │Process N│  ...  │
│  │  ~2KB   │ │  ~2KB   │ │  ~2KB   │ │  ~2KB   │       │
│  │ mailbox │ │ mailbox │ │ mailbox │ │ mailbox │       │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘       │
│        ↑           ↑           ↑           ↑           │
│        └───────────┴───────────┴───────────┘           │
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
| **bezgelor_world** | Game simulation | WorldManager, ZoneInstance, Handlers |

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

### One Process Per Zone

Each active zone shard runs as its own **Zone.Instance process**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Zone Instance Supervisor                     │
│                    (DynamicSupervisor)                          │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│  │ Zone.Instance    │  │ Zone.Instance    │  │ Zone.Instance  │ │
│  │ Thayd (1,1)      │  │ Illium (2,1)     │  │ Dungeon (3,5)  │ │
│  │                  │  │                  │  │                │ │
│  │ Entities: 150    │  │ Entities: 89     │  │ Entities: 12   │ │
│  │ Players: 45      │  │ Players: 23      │  │ Players: 5     │ │
│  │ Creatures: 105   │  │ Creatures: 66    │  │ Creatures: 7   │ │
│  └──────────────────┘  └──────────────────┘  └────────────────┘ │
│                                                                 │
│  Registry: {zone_id, instance_id} → pid                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Supervision Trees

### World Server Supervision Hierarchy

```
BezgelorWorld.Supervisor (one_for_one)
│
├── WorldManager (GenServer)
│   └── Central registry for all player sessions
│
├── CreatureManager (GenServer)
│   └── Spawns and manages NPC creatures
│
├── BuffManager (GenServer)
│   └── Tracks temporary effects on entities
│
├── CorpseManager (GenServer)
│   └── Manages lootable corpses
│
├── TickScheduler (GenServer)
│   └── Periodic game updates (buffs, etc.)
│
├── ZoneRegistry (Registry)
│   └── Maps {zone_id, instance_id} → Zone.Instance pid
│
├── Zone.InstanceSupervisor (DynamicSupervisor)
│   ├── Zone.Instance (Thayd, 1)
│   ├── Zone.Instance (Illium, 1)
│   ├── Zone.Instance (Dungeon, 5)
│   └── ... (created on demand)
│
├── Instance.Supervisor (DynamicSupervisor)
│   └── Dungeon/Raid instances
│
├── GroupFinder (GenServer)
│   └── Matchmaking queue
│
├── PvP Subsystem
│   ├── DuelManager
│   ├── BattlegroundSupervisor
│   ├── ArenaQueue
│   └── ...
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
│      │                                 │ Add to Zone.Instance       │
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
│ CONNECTION PROCESS STATE                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  %Connection{                                                        │
│    socket: #Port<0.1234>,          # TCP socket                      │
│    transport: :ranch_tcp,          # Transport module                │
│    connection_type: :world,        # :auth | :realm | :world         │
│    buffer: <<...>>,                # Incomplete packet data          │
│    encryption: %PacketCrypt{...},  # Encryption state                │
│    state: :authenticated,          # Connection state                │
│                                                                      │
│    session_data: %{                # Player session                  │
│      account_id: 12345,                                              │
│      character_id: 67890,                                            │
│      character_name: "PlayerOne",                                    │
│      entity_guid: 0x2000_0000_0001_0935,                            │
│      entity: %Entity{...},         # Current entity state            │
│      in_world: true,                                                 │
│      zone_id: 426,                 # Current zone                    │
│      instance_id: 1,                                                 │
│      in_combat: false,                                               │
│                                                                      │
│      # Quest system                                                  │
│      active_quests: %{quest_id => progress},                        │
│      completed_quest_ids: MapSet<[...]>,                            │
│      quest_dirty: false,           # Needs persistence               │
│                                                                      │
│      # Achievement tracking                                          │
│      achievement_handler: #PID<0.456.0>                             │
│    }                                                                 │
│  }                                                                   │
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

Zone instances created on demand:
- `DynamicSupervisor.start_child(ZoneSupervisor, {Zone.Instance, opts})`
- Automatic cleanup when empty
- Fault tolerance per zone

### 7. Registry for Named Lookups

```elixir
# Register zone instance
{:via, Registry, {ZoneRegistry, {zone_id, instance_id}}}

# Call by name tuple
Zone.Instance.add_entity({426, 1}, entity)
```

---

## Summary

Bezgelor's architecture leverages Elixir/OTP's strengths:

| Challenge | Solution |
|-----------|----------|
| Many concurrent players | Process per connection |
| Crash isolation | Supervision trees |
| Shared game state | Message passing, no locks |
| Fast static data access | ETS tables |
| Player session tracking | Central registry (WorldManager) |
| Zone management | Process per zone instance |
| Circular dependencies | Runtime handler registration |
| Code organization | Umbrella apps with clear boundaries |

The result is a highly concurrent, fault-tolerant server that can handle thousands of players while remaining maintainable and debuggable.
