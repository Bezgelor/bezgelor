# Phase 4-5 Infrastructure Design

**Status:** ✅ Complete

## Overview

This document captures the design decisions for completing the deferred Phase 4-5 infrastructure elements:

1. **Process Registry** - Abstraction layer over Elixir Registry
2. **bezgelor_data** - Static game data loading from JSON
3. **Zone Architecture** - Zone + Instance pattern with dynamic supervisors
4. **bezgelor_api** - Phoenix REST API for server status/admin

## Design Decisions

### 1. Implementation Priority

**Decision:** Design all components holistically, implement in dependency order.

**Order:**
1. Process Registry (foundation - everything depends on this)
2. bezgelor_data (static data needed by zones)
3. Zone + Instance architecture (uses registry + data)
4. Dynamic supervisors (manages zone lifecycle)
5. Phoenix API (queries all systems, optional)

### 2. Static Data Source

**Decision:** Hybrid approach - Export .tbl to JSON once, load JSON at runtime.

**Rationale:**
- WildStar .tbl files rarely change (game data is static)
- JSON is human-readable, easy to debug and modify
- Separate export tool can run offline when data updates
- Runtime loading is fast and simple

**Structure:**
```
priv/data/
├── creatures.json      # Creature templates
├── items.json          # Item definitions
├── spells.json         # Spell data
├── zones.json          # Zone definitions
└── quests.json         # Quest data
```

### 3. Zone Architecture

**Decision:** Zone + Instance pattern.

```
ZoneSupervisor
├── Zone "Algoroc" (template)
│   ├── Instance 1 (main world)
│   └── Instance 2 (overflow/phasing)
├── Zone "Whitevale"
│   └── Instance 1
└── Zone "Stormtalon's Lair" (dungeon)
    ├── Instance 1 (group A)
    ├── Instance 2 (group B)
    └── Instance N (created on demand)
```

**Features:**
- Zones are templates that spawn Instance GenServers
- Each instance has its own entity registry, spatial grid, state
- Dungeons/housing spawn fresh instances per group
- Open world can have overflow instances for capacity

### 4. Process Registry

**Decision:** Elixir Registry behind abstraction layer.

**Module:** `BezgelorCore.ProcessRegistry`

**Interface:**
```elixir
# Register a process
register(type, id)              # {:zone, "algoroc"}
register(type, id, metadata)    # {:player, 12345, %{name: "Bob"}}

# Lookup
lookup(type, id)                # Returns pid or nil
lookup_with_meta(type, id)      # Returns {pid, metadata} or nil

# Find all of type
list(type)                      # Returns [{id, pid}]
list_with_meta(type)            # Returns [{id, pid, metadata}]

# Unregister (usually automatic on process death)
unregister(type, id)
```

**Types:**
- `:zone_instance` - Zone instance processes
- `:player` - Player session processes
- `:creature` - Creature AI processes (future)
- `:guild` - Guild processes (future)

## Module Structure

### BezgelorCore.ProcessRegistry

```elixir
defmodule BezgelorCore.ProcessRegistry do
  @moduledoc """
  Process registry abstraction.

  Currently backed by Elixir Registry.
  Can be swapped to :gproc or other implementations.
  """

  @registry_name __MODULE__.Registry

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry_name)
  end

  def register(type, id, metadata \\ %{})
  def lookup(type, id)
  def list(type)
  # ...
end
```

### BezgelorData

```elixir
defmodule BezgelorData do
  @moduledoc """
  Static game data access.
  """

  # Creature templates
  def get_creature(id)
  def list_creatures()
  def creatures_by_zone(zone_id)

  # Items
  def get_item(id)
  def list_items()

  # Spells
  def get_spell(id)
  def list_spells()

  # Zones
  def get_zone(id)
  def list_zones()
end
```

### Zone Architecture

```elixir
defmodule BezgelorWorld.Zone.Supervisor do
  @moduledoc "Supervises all zone templates"
  use Supervisor
end

defmodule BezgelorWorld.Zone.Template do
  @moduledoc "Zone template - spawns instances"
  use GenServer

  def spawn_instance(zone_id, opts \\ [])
  def get_instance(zone_id, instance_id)
  def list_instances(zone_id)
end

defmodule BezgelorWorld.Zone.Instance do
  @moduledoc "Zone instance - actual game world shard"
  use GenServer

  # Entity management
  def add_entity(instance, entity)
  def remove_entity(instance, guid)
  def get_entity(instance, guid)

  # Spatial queries
  def entities_in_range(instance, position, radius)
  def broadcast(instance, message)
end
```

### Dynamic Supervisors

```elixir
defmodule BezgelorWorld.Zone.InstanceSupervisor do
  @moduledoc "Dynamic supervisor for zone instances"
  use DynamicSupervisor

  def start_instance(zone_id, opts)
  def stop_instance(zone_id, instance_id)
end

defmodule BezgelorWorld.PlayerSupervisor do
  @moduledoc "Dynamic supervisor for player sessions"
  use DynamicSupervisor

  def start_player(account_id, character_id)
  def stop_player(guid)
end
```

### Phoenix API

```elixir
# Router
scope "/api/v1", BezgelorApi do
  get "/status", StatusController, :index
  get "/zones", ZoneController, :index
  get "/zones/:id", ZoneController, :show
  get "/players/online", PlayerController, :online
end
```

## Migration Path

The abstraction layer allows future migration to :gproc if needed:

1. Create new `GprocRegistry` module implementing same interface
2. Add config option: `config :bezgelor_core, :registry_impl, :native | :gproc`
3. Update `ProcessRegistry` to delegate to configured implementation
4. Test thoroughly
5. Switch config

## Implementation Order

### Phase 1: Process Registry (Foundation)
- [x] Create `BezgelorCore.ProcessRegistry` module
- [x] Add Registry to supervision tree
- [x] Write tests for all operations
- [x] Update existing code to use registry

### Phase 2: bezgelor_data
- [x] Create JSON data files in priv/data/
- [x] Create `BezgelorData` application
- [x] Implement data loading on startup
- [x] Implement access functions
- [x] Write tests

### Phase 3: Zone Architecture
- [x] Create Zone.Supervisor
- [x] Create Zone.Template GenServer (implemented as Zone.Manager)
- [x] Create Zone.Instance GenServer
- [x] Create Zone.InstanceSupervisor (DynamicSupervisor)
- [x] Migrate WorldManager functionality to zones
- [x] Write tests

### Phase 4: Player Sessions
- [x] Create PlayerSupervisor (DynamicSupervisor)
- [x] Create Player GenServer (optional, can keep current approach)
- [x] Update connection to use registry

### Phase 5: Phoenix API
- [x] Create bezgelor_api Phoenix application
- [x] Add status endpoint
- [x] Add zone listing endpoint
- [x] Add player online endpoint
- [x] Write tests

---

## Implementation Notes

**Files Implemented:**

*Process Registry:*
- `apps/bezgelor_core/lib/bezgelor_core/process_registry.ex` - Registry abstraction layer

*bezgelor_data:*
- `apps/bezgelor_data/lib/bezgelor_data.ex` - Static game data access
- `apps/bezgelor_data/priv/data/*.json` - JSON data files

*Zone Architecture:*
- `apps/bezgelor_world/lib/bezgelor_world/zone/manager.ex` - Zone template management (named Manager instead of Template)
- `apps/bezgelor_world/lib/bezgelor_world/zone/instance.ex` - Zone instance GenServer
- `apps/bezgelor_world/lib/bezgelor_world/zone/instance_supervisor.ex` - Dynamic supervisor for instances

*Phoenix API:*
- `apps/bezgelor_api/lib/bezgelor_api/application.ex` - API application
- `apps/bezgelor_api/lib/bezgelor_api/router.ex` - API routes
- `apps/bezgelor_api/lib/bezgelor_api/controllers/status_controller.ex` - Server status
- `apps/bezgelor_api/lib/bezgelor_api/controllers/zone_controller.ex` - Zone information
- `apps/bezgelor_api/lib/bezgelor_api/controllers/player_controller.ex` - Online players

**Design Notes:**
- Zone.Template was implemented as Zone.Manager for clearer naming
- All infrastructure components fully operational
