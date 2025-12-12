# Remediation Implementation Plan

**Date:** 2025-12-11
**Status:** Ready for Implementation
**Reference:** `2025-12-11-critical-architecture-review.md`

---

## Phase 1: Critical Fixes

**Scope:** 5 high-impact changes addressing immediate scaling bottlenecks and security gaps

### 1.1 Spatial Grid for Zone Instance Range Queries

**Problem:** `zone/instance.ex:287-302` iterates all entities for every range query - O(n) complexity.

**Current Code:**
```elixir
def handle_call({:entities_in_range, {x, y, z}, radius}, _from, state) do
  radius_sq = radius * radius
  entities =
    state.entities
    |> Map.values()
    |> Enum.filter(fn entity ->
      {ex, ey, ez} = entity.position
      dx = ex - x
      dy = ey - y
      dz = ez - z
      dx * dx + dy * dy + dz * dz <= radius_sq
    end)
  {:reply, entities, state}
end
```

**Solution:** Implement a grid-based spatial index.

**Implementation:**

1. **Create `BezgelorCore.SpatialGrid` module:**

```elixir
defmodule BezgelorCore.SpatialGrid do
  @moduledoc """
  Grid-based spatial index for O(1) cell lookups + O(k) neighbor iteration.

  Divides the world into cells of fixed size. Range queries only check
  entities in relevant cells rather than all entities.
  """

  @default_cell_size 50.0  # 50 units per cell

  @type t :: %__MODULE__{
    cells: %{{integer(), integer(), integer()} => MapSet.t(non_neg_integer())},
    entity_positions: %{non_neg_integer() => {float(), float(), float()}},
    cell_size: float()
  }

  defstruct cells: %{}, entity_positions: %{}, cell_size: @default_cell_size

  @doc "Create a new spatial grid."
  def new(cell_size \\ @default_cell_size) do
    %__MODULE__{cell_size: cell_size}
  end

  @doc "Insert an entity at a position."
  def insert(%__MODULE__{} = grid, guid, {x, y, z}) do
    cell = position_to_cell({x, y, z}, grid.cell_size)

    cells = Map.update(grid.cells, cell, MapSet.new([guid]), &MapSet.put(&1, guid))
    positions = Map.put(grid.entity_positions, guid, {x, y, z})

    %{grid | cells: cells, entity_positions: positions}
  end

  @doc "Remove an entity from the grid."
  def remove(%__MODULE__{} = grid, guid) do
    case Map.get(grid.entity_positions, guid) do
      nil ->
        grid

      position ->
        cell = position_to_cell(position, grid.cell_size)

        cells = Map.update(grid.cells, cell, MapSet.new(), &MapSet.delete(&1, guid))
        positions = Map.delete(grid.entity_positions, guid)

        %{grid | cells: cells, entity_positions: positions}
    end
  end

  @doc "Update an entity's position."
  def update(%__MODULE__{} = grid, guid, new_position) do
    grid
    |> remove(guid)
    |> insert(guid, new_position)
  end

  @doc "Get all entity GUIDs within range of a position."
  def entities_in_range(%__MODULE__{} = grid, {x, y, z}, radius) do
    # Calculate which cells to check
    cells_to_check = cells_in_range({x, y, z}, radius, grid.cell_size)
    radius_sq = radius * radius

    # Gather entities from relevant cells
    cells_to_check
    |> Enum.flat_map(fn cell ->
      Map.get(grid.cells, cell, MapSet.new()) |> MapSet.to_list()
    end)
    |> Enum.filter(fn guid ->
      case Map.get(grid.entity_positions, guid) do
        nil -> false
        {ex, ey, ez} ->
          dx = ex - x
          dy = ey - y
          dz = ez - z
          dx * dx + dy * dy + dz * dz <= radius_sq
      end
    end)
  end

  # Private

  defp position_to_cell({x, y, z}, cell_size) do
    {floor(x / cell_size), floor(y / cell_size), floor(z / cell_size)}
  end

  defp cells_in_range({x, y, z}, radius, cell_size) do
    cells_radius = ceil(radius / cell_size)
    center = position_to_cell({x, y, z}, cell_size)
    {cx, cy, cz} = center

    for dx <- -cells_radius..cells_radius,
        dy <- -cells_radius..cells_radius,
        dz <- -cells_radius..cells_radius do
      {cx + dx, cy + dy, cz + dz}
    end
  end
end
```

2. **Update Zone.Instance state and callbacks:**

```elixir
# In init/1, add spatial grid to state:
state = %{
  zone_id: zone_id,
  instance_id: instance_id,
  zone_data: zone_data,
  entities: %{},
  spatial_grid: SpatialGrid.new(50.0),  # ADD THIS
  players: MapSet.new(),
  creatures: MapSet.new()
}

# In handle_cast({:add_entity, entity}, state):
spatial_grid = SpatialGrid.insert(state.spatial_grid, entity.guid, entity.position)
# ... update state with spatial_grid

# In handle_cast({:remove_entity, guid}, state):
spatial_grid = SpatialGrid.remove(state.spatial_grid, guid)
# ... update state with spatial_grid

# Replace handle_call({:entities_in_range, ...}):
def handle_call({:entities_in_range, position, radius}, _from, state) do
  guids = SpatialGrid.entities_in_range(state.spatial_grid, position, radius)
  entities = Enum.map(guids, &Map.get(state.entities, &1)) |> Enum.reject(&is_nil/1)
  {:reply, entities, state}
end
```

3. **Add position update function:**

```elixir
# New client API function
def update_entity_position({zone_id, instance_id}, guid, new_position) do
  GenServer.call(via_tuple(zone_id, instance_id), {:update_position, guid, new_position})
end

# Handler
def handle_call({:update_position, guid, new_position}, _from, state) do
  case Map.get(state.entities, guid) do
    nil ->
      {:reply, :error, state}
    entity ->
      updated_entity = %{entity | position: new_position}
      entities = Map.put(state.entities, guid, updated_entity)
      spatial_grid = SpatialGrid.update(state.spatial_grid, guid, new_position)
      {:reply, :ok, %{state | entities: entities, spatial_grid: spatial_grid}}
  end
end
```

**Testing:**
```elixir
# apps/bezgelor_core/test/spatial_grid_test.exs
defmodule BezgelorCore.SpatialGridTest do
  use ExUnit.Case

  alias BezgelorCore.SpatialGrid

  test "insert and query entities" do
    grid = SpatialGrid.new(10.0)
      |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
      |> SpatialGrid.insert(2, {15.0, 5.0, 0.0})
      |> SpatialGrid.insert(3, {100.0, 100.0, 0.0})

    # Entity 1 and 2 are within 15 units of origin
    result = SpatialGrid.entities_in_range(grid, {0.0, 0.0, 0.0}, 20.0)
    assert 1 in result
    assert 2 in result
    refute 3 in result
  end

  test "update position moves entity between cells" do
    grid = SpatialGrid.new(10.0)
      |> SpatialGrid.insert(1, {5.0, 5.0, 0.0})
      |> SpatialGrid.update(1, {95.0, 95.0, 0.0})

    refute 1 in SpatialGrid.entities_in_range(grid, {0.0, 0.0, 0.0}, 20.0)
    assert 1 in SpatialGrid.entities_in_range(grid, {100.0, 100.0, 0.0}, 20.0)
  end
end
```

**Complexity:**
- Before: O(n) per query
- After: O(k) where k = entities in nearby cells (typically < 50)

---

### 1.2 Name Index for WorldManager Session Lookups

**Problem:** `world_manager.ex:195-202` scans all sessions for name lookups - O(n) complexity.

**Current Code:**
```elixir
def handle_call({:find_session_by_name, character_name}, _from, state) do
  result =
    Enum.find(state.sessions, fn {_account_id, session} ->
      session.character_name != nil and
        String.downcase(session.character_name) == String.downcase(character_name)
    end)
  {:reply, result, state}
end
```

**Solution:** Add a name-to-account_id index map.

**Implementation:**

1. **Update state type and init:**

```elixir
@type state :: %{
  sessions: %{non_neg_integer() => session()},
  name_index: %{String.t() => non_neg_integer()},  # ADD THIS
  entities: %{non_neg_integer() => any()},
  next_guid_counter: non_neg_integer()
}

def init(_opts) do
  state = %{
    sessions: %{},
    name_index: %{},  # ADD THIS
    entities: %{},
    next_guid_counter: 1
  }
  {:ok, state}
end
```

2. **Update register_session to maintain index:**

```elixir
def handle_call({:register_session, account_id, character_id, character_name, connection_pid}, _from, state) do
  session = %{
    character_id: character_id,
    character_name: character_name,
    connection_pid: connection_pid,
    entity_guid: nil
  }

  sessions = Map.put(state.sessions, account_id, session)

  # Update name index
  name_index =
    if character_name do
      Map.put(state.name_index, String.downcase(character_name), account_id)
    else
      state.name_index
    end

  {:reply, :ok, %{state | sessions: sessions, name_index: name_index}}
end
```

3. **Update unregister_session to remove from index:**

```elixir
def handle_cast({:unregister_session, account_id}, state) do
  # Remove from name index if present
  name_index =
    case Map.get(state.sessions, account_id) do
      %{character_name: name} when is_binary(name) ->
        Map.delete(state.name_index, String.downcase(name))
      _ ->
        state.name_index
    end

  sessions = Map.delete(state.sessions, account_id)
  {:noreply, %{state | sessions: sessions, name_index: name_index}}
end
```

4. **Replace find_session_by_name with O(1) lookup:**

```elixir
def handle_call({:find_session_by_name, character_name}, _from, state) do
  result =
    case Map.get(state.name_index, String.downcase(character_name)) do
      nil -> nil
      account_id -> {account_id, Map.get(state.sessions, account_id)}
    end
  {:reply, result, state}
end
```

5. **Update find_session_by_name_in_state helper:**

```elixir
defp find_session_by_name_in_state(sessions, name_index, character_name) do
  case Map.get(name_index, String.downcase(character_name)) do
    nil -> nil
    account_id -> {account_id, Map.get(sessions, account_id)}
  end
end
```

**Complexity:**
- Before: O(n) per whisper
- After: O(1) per whisper

---

### 1.3 Shard CreatureManager by Zone

**Problem:** `creature_manager.ex` is a single process handling ALL creatures globally. AI updates capped at 100/tick.

**Current Code:** Single GenServer with `@max_creatures_per_tick 100`.

**Solution:** Create per-zone creature managers spawned by ZoneInstanceSupervisor.

**Implementation:**

1. **Create `BezgelorWorld.Creature.ZoneManager`:**

```elixir
defmodule BezgelorWorld.Creature.ZoneManager do
  @moduledoc """
  Per-zone creature manager.

  Each zone instance has its own ZoneManager handling creature AI, spawns,
  and state for that zone only.
  """

  use GenServer

  require Logger

  alias BezgelorCore.{AI, CreatureTemplate, Entity, Loot}
  alias BezgelorCore.ProcessRegistry

  @default_ai_tick_interval 1000
  @max_creatures_per_tick 100

  # Client API

  def start_link(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    instance_id = Keyword.fetch!(opts, :instance_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(zone_id, instance_id))
  end

  def via_tuple(zone_id, instance_id) do
    {:via, Registry, {ProcessRegistry.Registry, {:creature_manager, {zone_id, instance_id}}}}
  end

  def spawn_creature(zone_id, instance_id, template_id, position) do
    GenServer.call(via_tuple(zone_id, instance_id), {:spawn_creature, template_id, position})
  end

  def get_creature(zone_id, instance_id, guid) do
    GenServer.call(via_tuple(zone_id, instance_id), {:get_creature, guid})
  end

  def damage_creature(zone_id, instance_id, creature_guid, attacker_guid, damage) do
    GenServer.call(via_tuple(zone_id, instance_id), {:damage_creature, creature_guid, attacker_guid, damage})
  end

  # ... rest of API matches current CreatureManager but scoped to zone

  # Server callbacks

  def init(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    instance_id = Keyword.fetch!(opts, :instance_id)
    ai_tick_interval = Keyword.get(opts, :ai_tick_interval, @default_ai_tick_interval)

    state = %{
      zone_id: zone_id,
      instance_id: instance_id,
      creatures: %{},
      ai_tick_interval: ai_tick_interval
    }

    if ai_tick_interval > 0 do
      Process.send_after(self(), :ai_tick, ai_tick_interval)
    end

    Logger.info("Creature.ZoneManager started for zone #{zone_id} instance #{instance_id}")
    {:ok, state}
  end

  # ... handlers same as CreatureManager but zone-scoped
end
```

2. **Update `Zone.InstanceSupervisor` to spawn creature managers:**

```elixir
def start_instance(zone_id, opts) do
  instance_id = Keyword.get(opts, :instance_id, generate_instance_id())

  # Start the zone instance
  instance_spec = %{
    id: {:zone_instance, zone_id, instance_id},
    start: {Zone.Instance, :start_link, [[zone_id: zone_id, instance_id: instance_id] ++ opts]},
    restart: :temporary
  }

  # Start the creature manager for this zone
  creature_manager_spec = %{
    id: {:creature_manager, zone_id, instance_id},
    start: {Creature.ZoneManager, :start_link, [[zone_id: zone_id, instance_id: instance_id]]},
    restart: :temporary
  }

  {:ok, instance_pid} = DynamicSupervisor.start_child(__MODULE__, instance_spec)
  {:ok, _creature_pid} = DynamicSupervisor.start_child(__MODULE__, creature_manager_spec)

  {:ok, instance_pid, instance_id}
end
```

3. **Update handlers to route to zone-specific creature manager:**

```elixir
# In CombatHandler, instead of:
CreatureManager.damage_creature(creature_guid, attacker_guid, damage)

# Use:
Creature.ZoneManager.damage_creature(zone_id, instance_id, creature_guid, attacker_guid, damage)
```

4. **Keep global CreatureManager as router (optional):**

The global CreatureManager can be retained as a thin routing layer that forwards to zone-specific managers, or removed entirely if handlers know the zone context.

**Complexity:**
- Before: 1 process, 500+ creatures competing
- After: n processes (1 per zone), ~50-100 creatures each

---

### 1.4 Implement Encrypted Packet Handler

**Problem:** `encrypted_handler.ex:14-18` silently ignores encrypted packets.

**Current Code:**
```elixir
def handle(payload, state) do
  Logger.debug("EncryptedHandler: received #{byte_size(payload)} bytes")
  # TODO: Decrypt and re-dispatch inner packet
  {:ok, state}
end
```

**Solution:** Implement decryption using session key and re-dispatch.

**Implementation:**

```elixir
defmodule BezgelorProtocol.Handler.EncryptedHandler do
  @moduledoc """
  Handles encrypted packets (opcode 0x0077).

  Decrypts the payload using the session encryption key,
  then dispatches the inner packet to the appropriate handler.
  """

  @behaviour BezgelorProtocol.Handler

  alias BezgelorCrypto.PacketCrypto
  alias BezgelorProtocol.{PacketReader, PacketRegistry}

  require Logger

  @impl true
  def handle(payload, state) do
    case decrypt_and_dispatch(payload, state) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:error, reason} ->
        Logger.warning("EncryptedHandler: failed to process - #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp decrypt_and_dispatch(payload, state) do
    # Get encryption key from connection state
    encryption_key = Map.get(state, :encryption_key)

    if is_nil(encryption_key) do
      Logger.warning("EncryptedHandler: no encryption key available")
      {:error, :no_encryption_key}
    else
      with {:ok, decrypted} <- PacketCrypto.decrypt(payload, encryption_key),
           {:ok, inner_opcode, inner_payload} <- parse_inner_packet(decrypted),
           handler when not is_nil(handler) <- PacketRegistry.lookup(inner_opcode) do

        Logger.debug("EncryptedHandler: dispatching #{inner_opcode} (#{byte_size(inner_payload)} bytes)")
        handler.handle(inner_payload, state)
      else
        nil ->
          {:error, :unknown_inner_opcode}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp parse_inner_packet(decrypted) do
    reader = PacketReader.new(decrypted)

    with {:ok, opcode_int, reader} <- PacketReader.read_uint16(reader),
         {:ok, opcode} <- opcode_to_atom(opcode_int) do
      {:ok, opcode, PacketReader.remaining(reader)}
    end
  end

  defp opcode_to_atom(opcode_int) do
    # Map integer opcodes to atoms
    # This should be centralized in packet_opcodes.ex
    case BezgelorProtocol.PacketOpcodes.to_atom(opcode_int) do
      nil -> {:error, {:unknown_opcode, opcode_int}}
      atom -> {:ok, atom}
    end
  end
end
```

**Note:** This requires `PacketCrypto.decrypt/2` to be implemented in `bezgelor_crypto`. The actual encryption algorithm depends on the WildStar protocol analysis.

---

### 1.5 Add Session Timestamp Validation

**Problem:** `world_auth_handler.ex:61-78` has no session TTL - old session keys remain valid indefinitely.

**Solution:** Add created_at timestamp and validate freshness.

**Implementation:**

1. **Update session storage in auth flow:**

```elixir
# In BezgelorAuth, when creating session keys:
def create_session(account_id, session_key) do
  session = %{
    account_id: account_id,
    session_key: session_key,
    created_at: System.system_time(:second),
    expires_at: System.system_time(:second) + @session_ttl_seconds
  }
  :ets.insert(:auth_sessions, {account_id, session})
end

@session_ttl_seconds 3600  # 1 hour
```

2. **Update world auth handler validation:**

```elixir
# In WorldAuthHandler
defp validate_session(account_id, provided_key) do
  case :ets.lookup(:auth_sessions, account_id) do
    [] ->
      {:error, :session_not_found}

    [{^account_id, session}] ->
      now = System.system_time(:second)

      cond do
        now > session.expires_at ->
          :ets.delete(:auth_sessions, account_id)
          {:error, :session_expired}

        session.session_key != provided_key ->
          {:error, :invalid_session_key}

        true ->
          {:ok, session}
      end
  end
end
```

3. **Add periodic cleanup (in auth application):**

```elixir
defmodule BezgelorAuth.SessionCleaner do
  use GenServer

  @cleanup_interval_ms 60_000  # 1 minute

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  def handle_info(:cleanup, state) do
    cleanup_expired_sessions()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_expired_sessions do
    now = System.system_time(:second)

    :ets.foldl(fn {account_id, session}, acc ->
      if now > session.expires_at do
        :ets.delete(:auth_sessions, account_id)
      end
      acc
    end, nil, :auth_sessions)
  end
end
```

---

## Phase 2: High Priority Fixes

**Scope:** 5 important improvements for maintainability and database performance

### 2.1 Break Protocol to World Dependency

**Problem:** `packet_registry.ex:91-98` hardcodes `BezgelorWorld.Handler.*` references in protocol layer.

**Current Code:**
```elixir
defp default_handlers do
  %{
    client_chat: BezgelorWorld.Handler.ChatHandler,
    client_cast_spell: BezgelorWorld.Handler.SpellHandler,
    # ...
  }
end
```

**Solution:** Register handlers at application startup instead of hardcoding.

**Implementation:**

1. **Update PacketRegistry to have minimal defaults:**

```elixir
defmodule BezgelorProtocol.PacketRegistry do
  defp default_handlers do
    %{
      # Only protocol-layer handlers that don't depend on world
      client_hello_auth: Handler.AuthHandler,
      client_encrypted: Handler.EncryptedHandler,
      client_hello_auth_realm: Handler.RealmAuthHandler,
      client_hello_realm: Handler.WorldAuthHandler,
      client_character_create: Handler.CharacterCreateHandler,
      client_character_select: Handler.CharacterSelectHandler,
      client_character_delete: Handler.CharacterDeleteHandler,
      client_entered_world: Handler.WorldEntryHandler,
      client_movement: Handler.MovementHandler
    }
  end
end
```

2. **Create registration module in bezgelor_world:**

```elixir
defmodule BezgelorWorld.HandlerRegistration do
  @moduledoc """
  Registers world handlers with the packet registry at application startup.
  """

  alias BezgelorProtocol.PacketRegistry
  alias BezgelorWorld.Handler.{ChatHandler, SpellHandler, CombatHandler}

  def register_all do
    PacketRegistry.register(:client_chat, ChatHandler)
    PacketRegistry.register(:client_cast_spell, SpellHandler)
    PacketRegistry.register(:client_cancel_cast, SpellHandler)
    PacketRegistry.register(:client_set_target, CombatHandler)
    PacketRegistry.register(:client_respawn, CombatHandler)
    # ... register other world handlers
  end
end
```

3. **Call registration in bezgelor_world application start:**

```elixir
defmodule BezgelorWorld.Application do
  def start(_type, _args) do
    # Register handlers before starting supervision tree
    BezgelorWorld.HandlerRegistration.register_all()

    children = [
      # ...
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**Benefit:** Protocol layer now has zero compile-time dependency on world layer.

---

### 2.2 Fix N+1 Query in Inventory.find_empty_slot

**Problem:** `inventory.ex:288-319` executes 1 + N queries (1 for bags, N for items in each bag).

**Solution:** Single query with join.

**Implementation:**

```elixir
def find_empty_slot(character_id, container_type \\ :bag) do
  # Single query: get all bags and their items in one shot
  query = from b in Bag,
    left_join: i in InventoryItem, on: i.bag_id == b.id,
    where: b.character_id == ^character_id and b.container_type == ^container_type,
    select: {b, i}

  results = Repo.all(query)

  # Group items by bag
  bags_with_items =
    results
    |> Enum.group_by(fn {bag, _item} -> bag end, fn {_bag, item} -> item end)

  # Find first bag with empty slot
  Enum.find_value(bags_with_items, fn {bag, items} ->
    items = Enum.reject(items, &is_nil/1)
    occupied_slots = MapSet.new(items, & &1.slot)

    Enum.find(0..(bag.slots - 1), fn slot ->
      not MapSet.member?(occupied_slots, slot)
    end)
    |> case do
      nil -> nil
      slot -> {bag.id, slot}
    end
  end)
end
```

**Complexity:**
- Before: 1 + N queries (6 for 5 bags)
- After: 1 query

---

### 2.3 Fix In-Memory Promotion Filtering

**Problem:** `storefront.ex:194-214` loads all promotions and filters in Elixir.

**Solution:** Filter in database query.

**Implementation:**

```elixir
def get_applicable_promotion(item_id) do
  now = DateTime.utc_now()

  StorePromotion
  |> where([p], p.is_active == true)
  |> where([p], is_nil(p.start_date) or p.start_date <= ^now)
  |> where([p], is_nil(p.end_date) or p.end_date >= ^now)
  |> where([p], ^item_id in p.item_ids or p.applies_to_all == true)
  |> order_by([p], desc: p.discount_percent)
  |> limit(1)
  |> Repo.one()
end
```

**Note:** If `item_ids` is an array column, use `fragment("? = ANY(?)", ^item_id, p.item_ids)` instead.

---

### 2.4 Add Missing Database Indexes

**Problem:** Several frequently-queried columns lack indexes.

**Implementation:**

Create migration `priv/repo/migrations/YYYYMMDDHHMMSS_add_performance_indexes.exs`:

```elixir
defmodule BezgelorDb.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    # Work orders - queried by status and expiration
    create index(:work_orders, [:status, :expires_at])

    # Schematic discoveries - queried by schematic_id for duplicate checks
    create index(:schematic_discoveries, [:schematic_id])

    # Store promotions - queried by active status and dates
    create index(:store_promotions, [:is_active, :start_date, :end_date])

    # Inventory items - queried by bag_id for slot lookups
    create index(:inventory_items, [:bag_id, :slot])

    # Characters - queried by account_id frequently
    create index(:characters, [:account_id, :deleted_at])
  end
end
```

---

### 2.5 Shard BuffManager by Entity

**Problem:** Similar to CreatureManager, BuffManager is a single global process.

**Solution:** Store buffs as part of entity state or shard by entity GUID hash.

**Implementation Option A: Entity-Local Buffs**

```elixir
# Add to Entity struct
defmodule BezgelorCore.Entity do
  defstruct [
    # ... existing fields
    buffs: %{}  # %{buff_id => %{expires_at: ..., stacks: ..., ...}}
  ]

  def add_buff(entity, buff_id, buff_data) do
    buffs = Map.put(entity.buffs, buff_id, buff_data)
    %{entity | buffs: buffs}
  end

  def remove_buff(entity, buff_id) do
    %{entity | buffs: Map.delete(entity.buffs, buff_id)}
  end

  def tick_buffs(entity, now) do
    expired = Enum.filter(entity.buffs, fn {_id, data} -> data.expires_at <= now end)
    buffs = Map.drop(entity.buffs, Enum.map(expired, &elem(&1, 0)))
    {%{entity | buffs: buffs}, expired}
  end
end
```

**Implementation Option B: Sharded BuffManagers**

```elixir
defmodule BezgelorWorld.BuffManager.Shard do
  # Similar pattern to Creature.ZoneManager
  # Key by hash(guid) % num_shards
end
```

---

---

## Phase 3: Medium Priority Fixes

**Scope:** 5 improvements for code quality, security hardening, and maintainability

### 3.1 Add Handler Middleware for Cross-Cutting Concerns

**Problem:** 24 handlers duplicate common patterns:
- "Player in world" validation (repeated in chat, spell, inventory, combat handlers)
- Session data extraction
- Logging patterns
- Error response formatting

**Current Pattern (ChatHandler:49-52):**
```elixir
defp process_chat(packet, state) do
  unless state.session_data[:in_world] do
    Logger.warning("Chat received before player entered world")
    {:error, :not_in_world}
  else
    # ... actual logic
  end
end
```

**Solution:** Create a handler middleware pipeline.

**Implementation:**

1. **Create `BezgelorWorld.Handler.Middleware` module:**

```elixir
defmodule BezgelorWorld.Handler.Middleware do
  @moduledoc """
  Middleware pipeline for world handlers.

  Provides composable validation and pre-processing steps.
  """

  require Logger

  @type middleware_result :: {:ok, map()} | {:error, atom(), map()}

  @doc """
  Run a handler function with middleware pipeline.

  ## Example

      Middleware.run(state, [
        &require_in_world/1,
        &extract_entity/1
      ], fn context ->
        # Handler logic with guaranteed context
        do_something(context.entity, context.session)
      end)
  """
  def run(state, middlewares, handler_fn) do
    context = %{
      state: state,
      session: state.session_data,
      entity: nil,
      entity_guid: nil,
      character_name: nil
    }

    case run_middlewares(middlewares, context) do
      {:ok, context} ->
        handler_fn.(context)

      {:error, reason, context} ->
        {:error, reason}
    end
  end

  defp run_middlewares([], context), do: {:ok, context}

  defp run_middlewares([middleware | rest], context) do
    case middleware.(context) do
      {:ok, context} -> run_middlewares(rest, context)
      {:error, reason} -> {:error, reason, context}
    end
  end

  # Standard middleware functions

  @doc "Require player to be in world."
  def require_in_world(%{session: session} = context) do
    if session[:in_world] do
      {:ok, context}
    else
      Logger.warning("Action received before player entered world")
      {:error, :not_in_world}
    end
  end

  @doc "Extract entity data into context."
  def extract_entity(%{session: session} = context) do
    context = %{
      context
      | entity: session[:entity],
        entity_guid: session[:entity_guid],
        character_name: session[:character_name]
    }
    {:ok, context}
  end

  @doc "Require entity to be alive."
  def require_alive(%{entity: entity} = context) do
    if entity && entity.health > 0 do
      {:ok, context}
    else
      {:error, :dead}
    end
  end

  @doc "Require valid target."
  def require_target(%{entity: entity} = context) do
    if entity && entity.target_guid do
      {:ok, %{context | target_guid: entity.target_guid}}
    else
      {:error, :no_target}
    end
  end

  @doc "Log handler entry."
  def log_entry(handler_name) do
    fn context ->
      Logger.debug("#{handler_name}: processing for #{context.character_name}")
      {:ok, context}
    end
  end
end
```

2. **Refactor handlers to use middleware:**

```elixir
defmodule BezgelorWorld.Handler.ChatHandler do
  alias BezgelorWorld.Handler.Middleware

  @impl true
  def handle(payload, state) do
    case ClientChat.read(PacketReader.new(payload)) do
      {:ok, packet, _reader} ->
        Middleware.run(state, [
          &Middleware.require_in_world/1,
          &Middleware.extract_entity/1
        ], fn context ->
          process_chat(packet, context)
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_chat(packet, context) do
    # No more in_world check needed - guaranteed by middleware
    case ChatCommand.parse(packet.message) do
      {:chat, channel, message} ->
        handle_chat(channel, message, context)
      # ...
    end
  end
end
```

3. **Create common error response helper:**

```elixir
defmodule BezgelorWorld.Handler.Response do
  @moduledoc "Standard response helpers for handlers."

  alias BezgelorProtocol.PacketWriter

  def error_packet(opcode, error_code, state) do
    writer = PacketWriter.new()
      |> PacketWriter.write_uint8(error_code)
    {:reply, opcode, PacketWriter.to_binary(writer), state}
  end

  def success_packet(opcode, packet_struct, write_fn, state) do
    writer = PacketWriter.new()
    {:ok, writer} = write_fn.(packet_struct, writer)
    {:reply, opcode, PacketWriter.to_binary(writer), state}
  end
end
```

**Benefit:** Removes ~200 lines of duplicated validation code across handlers.

---

### 3.2 Implement Pagination for Store Queries

**Problem:** `Store.list/1` returns entire tables, potentially 50,000+ items.

**Current Code (store.ex:64-67):**
```elixir
def list(table) do
  :ets.tab2list(table_name(table))
  |> Enum.map(fn {_id, data} -> data end)
end
```

**Solution:** Add paginated list functions using `:ets.match/3` continuation.

**Implementation:**

```elixir
defmodule BezgelorData.Store do
  @default_page_size 100

  @doc """
  List items with pagination.

  Returns `{items, continuation}` where continuation is nil when no more pages.

  ## Example

      {items, cont} = Store.list_paginated(:items, 50)
      {more_items, cont2} = Store.list_continue(cont)
  """
  @spec list_paginated(atom(), pos_integer()) :: {[map()], term() | nil}
  def list_paginated(table, limit \\ @default_page_size) do
    table_name = table_name(table)

    case :ets.match(table_name, {:"$1", :"$2"}, limit) do
      {matches, continuation} ->
        items = Enum.map(matches, fn [_id, data] -> data end)
        {items, continuation}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  Continue paginated listing.
  """
  @spec list_continue(term()) :: {[map()], term() | nil}
  def list_continue(continuation) do
    case :ets.match(continuation) do
      {matches, new_continuation} ->
        items = Enum.map(matches, fn [_id, data] -> data end)
        {items, new_continuation}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  List items matching a filter with pagination.

  Uses `:ets.select/3` for efficient server-side filtering.
  """
  @spec list_filtered(atom(), (map() -> boolean()), pos_integer()) :: {[map()], term() | nil}
  def list_filtered(table, filter_fn, limit \\ @default_page_size) do
    # For complex filters, we still need to iterate, but we can limit results
    table_name = table_name(table)

    # Use match_spec for simple filters when possible
    match_spec = [{
      {:"$1", :"$2"},
      [],
      [:"$2"]
    }]

    case :ets.select(table_name, match_spec, limit) do
      {items, continuation} ->
        filtered = Enum.filter(items, filter_fn)
        {filtered, continuation}

      :"$end_of_table" ->
        {[], nil}
    end
  end

  @doc """
  Stream all items from a table efficiently.

  Uses continuation-based iteration to avoid loading entire table.
  """
  @spec stream(atom()) :: Enumerable.t()
  def stream(table) do
    Stream.resource(
      fn -> list_paginated(table, @default_page_size) end,
      fn
        {[], nil} -> {:halt, nil}
        {items, continuation} ->
          next = if continuation, do: list_continue(continuation), else: {[], nil}
          {items, next}
      end,
      fn _ -> :ok end
    )
  end
end
```

**Usage in handlers:**

```elixir
# Instead of loading all schematics:
# schematics = Store.list(:tradeskill_schematics)

# Stream with filtering:
schematics =
  Store.stream(:tradeskill_schematics)
  |> Enum.filter(fn s -> s.profession_id == profession_id end)
  |> Enum.take(50)
```

---

### 3.3 Add Input Validation to Packets

**Problem:** Missing validation for packet fields allows exploits:
- Position can be NaN/Inf (out-of-world)
- String fields have no length limits (memory DOS)
- Race/class IDs not validated (invalid data)

**Solution:** Add validation layer to packet parsing.

**Implementation:**

1. **Create `BezgelorProtocol.Validation` module:**

```elixir
defmodule BezgelorProtocol.Validation do
  @moduledoc """
  Packet field validation utilities.
  """

  @max_string_length 4096
  @max_name_length 64
  @max_chat_length 1024

  # Position validation

  @doc "Validate a position tuple contains valid floats."
  def validate_position({x, y, z}) do
    cond do
      not is_number(x) or not is_number(y) or not is_number(z) ->
        {:error, :invalid_position_type}

      is_nan_or_inf(x) or is_nan_or_inf(y) or is_nan_or_inf(z) ->
        {:error, :invalid_position_value}

      abs(x) > 100_000 or abs(y) > 100_000 or abs(z) > 100_000 ->
        {:error, :position_out_of_bounds}

      true ->
        :ok
    end
  end

  defp is_nan_or_inf(val) when is_float(val) do
    val != val or val == :math.inf() or val == -:math.inf()
  end
  defp is_nan_or_inf(_), do: false

  # String validation

  @doc "Validate a string field."
  def validate_string(str, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, @max_string_length)
    allow_empty = Keyword.get(opts, :allow_empty, true)

    cond do
      not is_binary(str) ->
        {:error, :not_a_string}

      not allow_empty and byte_size(str) == 0 ->
        {:error, :empty_string}

      byte_size(str) > max_length ->
        {:error, :string_too_long}

      not String.valid?(str) ->
        {:error, :invalid_utf8}

      true ->
        :ok
    end
  end

  @doc "Validate a character name."
  def validate_name(name) do
    with :ok <- validate_string(name, max_length: @max_name_length, allow_empty: false) do
      # Additional name rules
      cond do
        not Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9]*$/, name) ->
          {:error, :invalid_name_format}

        String.length(name) < 3 ->
          {:error, :name_too_short}

        true ->
          :ok
      end
    end
  end

  @doc "Validate a chat message."
  def validate_chat_message(message) do
    validate_string(message, max_length: @max_chat_length)
  end

  # Enum validation

  @doc "Validate value is in allowed set."
  def validate_enum(value, allowed) when is_list(allowed) do
    if value in allowed do
      :ok
    else
      {:error, {:invalid_enum, value, allowed}}
    end
  end

  # Range validation

  @doc "Validate integer is in range."
  def validate_range(value, min, max) when is_integer(value) do
    if value >= min and value <= max do
      :ok
    else
      {:error, {:out_of_range, value, min, max}}
    end
  end
end
```

2. **Add validation to packet read:**

```elixir
defmodule BezgelorProtocol.Packets.World.ClientMovement do
  alias BezgelorProtocol.Validation

  def read(reader) do
    with {:ok, x, reader} <- PacketReader.read_float(reader),
         {:ok, y, reader} <- PacketReader.read_float(reader),
         {:ok, z, reader} <- PacketReader.read_float(reader),
         :ok <- Validation.validate_position({x, y, z}),
         # ... rest of parsing
    do
      {:ok, %__MODULE__{position: {x, y, z}, ...}, reader}
    end
  end
end
```

3. **Add validation to string reads in PacketReader:**

```elixir
defmodule BezgelorProtocol.PacketReader do
  @max_string_bytes 65535

  def read_wide_string(reader, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, @max_string_bytes)

    with {:ok, length, reader} <- read_uint16(reader) do
      if length > max_length do
        {:error, :string_too_long}
      else
        # ... existing read logic
      end
    end
  end
end
```

---

### 3.4 Remove ProcessRegistry Abstraction

**Problem:** ProcessRegistry (250 lines) wraps Elixir Registry but is being bypassed directly.

**Evidence (zone/instance.ex:61):**
```elixir
def via_tuple(zone_id, instance_id) do
  {:via, Registry, {ProcessRegistry.Registry, {:zone_instance, {zone_id, instance_id}}}}
end
```

**Solution:** Remove abstraction, use Registry directly with a consistent naming pattern.

**Implementation:**

1. **Define registry names centrally:**

```elixir
# In config/config.exs or dedicated module
defmodule BezgelorCore.Registries do
  @moduledoc "Central registry name definitions."

  def process_registry, do: BezgelorCore.ProcessRegistry
  def zone_registry, do: BezgelorWorld.ZoneRegistry
  def player_registry, do: BezgelorWorld.PlayerRegistry
end
```

2. **Update supervision tree to start registries:**

```elixir
# In BezgelorCore.Application
children = [
  {Registry, keys: :unique, name: BezgelorCore.ProcessRegistry}
]

# In BezgelorWorld.Application
children = [
  {Registry, keys: :unique, name: BezgelorWorld.ZoneRegistry},
  {Registry, keys: :unique, name: BezgelorWorld.PlayerRegistry},
  # ...
]
```

3. **Update via_tuple to use Registry directly:**

```elixir
defmodule BezgelorWorld.Zone.Instance do
  def via_tuple(zone_id, instance_id) do
    {:via, Registry, {BezgelorWorld.ZoneRegistry, {:zone_instance, zone_id, instance_id}}}
  end
end
```

4. **Create thin helper for common operations:**

```elixir
defmodule BezgelorWorld.ProcessLookup do
  @moduledoc "Lookup helpers for world processes."

  def find_zone(zone_id, instance_id) do
    case Registry.lookup(BezgelorWorld.ZoneRegistry, {:zone_instance, zone_id, instance_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  def list_zones do
    Registry.select(BezgelorWorld.ZoneRegistry, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
    ])
  end
end
```

5. **Remove `apps/bezgelor_core/lib/bezgelor_core/process_registry.ex`**

**Benefit:** ~200 lines removed, simpler direct Registry usage, no abstraction leakage.

---

### 3.5 Document Protocol Deviations from NexusForever

**Problem:** No documentation of where Bezgelor differs from NexusForever implementation.

**Solution:** Create comprehensive deviation documentation.

**Implementation:**

Create `docs/protocol-deviations.md`:

```markdown
# Protocol Deviations from NexusForever

This document tracks intentional differences between Bezgelor and the
NexusForever C# implementation.

## Packet Handling

### Different Opcodes

| Feature | NexusForever | Bezgelor | Reason |
|---------|--------------|----------|--------|
| ... | ... | ... | ... |

### Modified Packet Structures

| Packet | Field | Change | Reason |
|--------|-------|--------|--------|
| ... | ... | ... | ... |

## Authentication

### Session Key Generation

NexusForever: [describe C# implementation]
Bezgelor: [describe Elixir implementation]
Reason: [cryptographic or compatibility reason]

## Game Logic Differences

### Combat Calculations

...

## Known Incompatibilities

List of client versions and features that may not work:

- Feature X requires client patch Y
- ...

## Verification Needed

Items that haven't been verified against original client:

- [ ] Encrypted packet decryption
- [ ] ...
```

**Process:**
1. Review NexusForever source for each packet handler
2. Document any intentional deviations
3. Flag areas needing verification
4. Update as implementation progresses

---

## Phase 4: Low Priority Fixes (Ongoing)

**Scope:** 4 improvements for long-term code health and optimization

### 4.1 Strengthen Context Modules - Fix Repo Leakage

**Problem:** Handlers directly access `Repo` instead of going through context modules.

**Example pattern to fix:**
```elixir
# BAD: Handler directly queries Repo
def handle_something(state) do
  character = Repo.get(Character, state.character_id)
  items = Repo.all(from i in InventoryItem, where: i.character_id == ^character.id)
end

# GOOD: Handler uses context module
def handle_something(state) do
  character = Characters.get_character(state.character_id)
  items = Inventory.list_items(character.id)
end
```

**Solution:** Audit and refactor handlers to use context modules.

**Implementation:**

1. **Audit current Repo usage:**

```bash
# Find direct Repo calls in handlers
grep -r "Repo\." apps/bezgelor_world/lib/bezgelor_world/handler/
grep -r "Repo\." apps/bezgelor_protocol/lib/bezgelor_protocol/handler/
```

2. **Add missing context functions:**

```elixir
defmodule BezgelorDb.Inventory do
  # Add functions handlers need that are missing

  @doc "Get items with preloaded item definitions."
  def list_items_with_defs(character_id) do
    InventoryItem
    |> where([i], i.character_id == ^character_id)
    |> preload(:item_definition)
    |> Repo.all()
  end

  @doc "Batch insert items."
  def insert_items(items) do
    Repo.insert_all(InventoryItem, items)
  end
end
```

3. **Refactor handlers:**

```elixir
# Before
def handle_loot(creature_guid, state) do
  items = Repo.all(from i in LootDrop, where: i.creature_guid == ^creature_guid)
  for item <- items do
    Repo.insert(%InventoryItem{...})
  end
end

# After
def handle_loot(creature_guid, state) do
  items = Loot.get_drops(creature_guid)
  Inventory.add_items(state.character_id, items)
end
```

**Benefit:** Cleaner separation, easier testing, single source of query logic.

---

### 4.2 Reorganize World App - Extract Subsystems

**Problem:** `bezgelor_world` has 24 handlers + 6 subsystems with no organization.

**Current Structure:**
```
bezgelor_world/lib/bezgelor_world/
├── handler/           # 24 files, mixed responsibilities
├── encounter/         # Boss mechanics
├── loot/              # Loot distribution
├── instance/          # Dungeon instances
├── pvp/               # PvP systems
├── mythic_plus/       # M+ mechanics
└── group_finder/      # Group finder
```

**Solution:** Create sub-contexts within world app.

**Implementation:**

```
bezgelor_world/lib/bezgelor_world/
├── combat/
│   ├── handler.ex         # CombatHandler
│   ├── spell_handler.ex   # SpellHandler
│   ├── damage.ex          # Damage calculations
│   └── threat.ex          # Threat management
├── social/
│   ├── handler.ex         # ChatHandler, SocialHandler
│   ├── guild_handler.ex
│   └── mail_handler.ex
├── economy/
│   ├── inventory_handler.ex
│   ├── storefront_handler.ex
│   └── tradeskill_handler.ex
├── progression/
│   ├── quest_handler.ex
│   ├── achievement_handler.ex
│   ├── reputation_handler.ex
│   └── path_handler.ex
├── content/
│   ├── instance/
│   ├── encounter/
│   ├── mythic_plus/
│   └── event_handler.ex
├── pvp/
│   ├── duel_handler.ex
│   ├── battleground_handler.ex
│   └── arena/
└── zone/
    ├── instance.ex
    ├── manager.ex
    └── creature_manager.ex
```

**Migration Steps:**

1. Create new directory structure
2. Move files one subsystem at a time
3. Update module names (e.g., `BezgelorWorld.Combat.Handler`)
4. Update handler registration
5. Update imports/aliases in dependent code

---

### 4.3 Add Secondary ETS Indexes

**Problem:** Many ETS queries filter in Elixir after loading data.

**Current Pattern (store.ex):**
```elixir
def get_schematics_for_profession(profession_id) do
  list(:tradeskill_schematics)  # Load ALL schematics
  |> Enum.filter(fn s -> s.profession_id == profession_id end)  # Filter in memory
end
```

**Solution:** Create secondary index tables.

**Implementation:**

```elixir
defmodule BezgelorData.Store do
  # Secondary index tables
  @index_tables [
    :schematics_by_profession,  # profession_id -> [schematic_id]
    :items_by_type,             # item_type -> [item_id]
    :creatures_by_zone,         # zone_id -> [creature_id]
    :spells_by_class            # class_id -> [spell_id]
  ]

  def init(_opts) do
    # Create primary tables
    for table <- @tables do
      :ets.new(table_name(table), [:set, :public, :named_table, read_concurrency: true])
    end

    # Create index tables (bag allows multiple values per key)
    for table <- @index_tables do
      :ets.new(table_name(table), [:bag, :public, :named_table, read_concurrency: true])
    end

    load_all_data()
    {:ok, %{}}
  end

  # When loading schematics, also populate index
  defp load_table(:tradeskill_schematics, json_file, key) do
    # ... load primary table ...

    # Build secondary index
    index_table = table_name(:schematics_by_profession)
    :ets.delete_all_objects(index_table)

    for schematic <- schematics do
      :ets.insert(index_table, {schematic.profession_id, schematic.id})
    end
  end

  # Fast lookup using index
  def get_schematics_for_profession(profession_id) do
    index_table = table_name(:schematics_by_profession)
    primary_table = table_name(:tradeskill_schematics)

    # O(k) lookup via index instead of O(n) scan
    schematic_ids =
      :ets.lookup(index_table, profession_id)
      |> Enum.map(fn {_prof_id, schematic_id} -> schematic_id end)

    # Batch lookup primary records
    for id <- schematic_ids do
      case :ets.lookup(primary_table, id) do
        [{^id, schematic}] -> schematic
        [] -> nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end
end
```

**Indexes to Add:**

| Index Table | Key | Value | Use Case |
|-------------|-----|-------|----------|
| schematics_by_profession | profession_id | schematic_id | Crafting UI |
| items_by_type | item_type | item_id | Loot tables |
| creatures_by_zone | zone_id | creature_id | Zone spawning |
| spells_by_class | class_id | spell_id | Spellbook |

---

### 4.4 Implement Zone-Based Chat Routing

**Problem:** All chat broadcasts to all players regardless of zone.

**Current Code (world_manager.ex:265-281):**
```elixir
def handle_cast({:broadcast_chat, sender_guid, sender_name, channel, message, _position}, state) do
  # Broadcasts to ALL sessions
  Enum.each(state.sessions, fn {_account_id, session} ->
    if session.entity_guid != sender_guid do
      send_chat_to_connection(...)
    end
  end)
end
```

**Solution:** Route chat through zone instances.

**Implementation:**

1. **Add zone_id to session tracking:**

```elixir
@type session :: %{
  character_id: non_neg_integer(),
  character_name: String.t() | nil,
  connection_pid: pid(),
  entity_guid: non_neg_integer() | nil,
  zone_id: non_neg_integer() | nil,       # ADD
  instance_id: non_neg_integer() | nil    # ADD
}
```

2. **Update session registration to include zone:**

```elixir
def update_session_zone(account_id, zone_id, instance_id) do
  GenServer.cast(__MODULE__, {:update_zone, account_id, zone_id, instance_id})
end

def handle_cast({:update_zone, account_id, zone_id, instance_id}, state) do
  state =
    case Map.get(state.sessions, account_id) do
      nil -> state
      session ->
        session = %{session | zone_id: zone_id, instance_id: instance_id}
        %{state | sessions: Map.put(state.sessions, account_id, session)}
    end
  {:noreply, state}
end
```

3. **Add zone index for efficient lookup:**

```elixir
@type state :: %{
  sessions: %{non_neg_integer() => session()},
  name_index: %{String.t() => non_neg_integer()},
  zone_index: %{{non_neg_integer(), non_neg_integer()} => MapSet.t(non_neg_integer())},  # ADD
  # ...
}

# Maintain zone_index when updating zone
defp add_to_zone_index(zone_index, zone_id, instance_id, account_id) do
  key = {zone_id, instance_id}
  Map.update(zone_index, key, MapSet.new([account_id]), &MapSet.put(&1, account_id))
end
```

4. **Route chat by channel type:**

```elixir
def handle_cast({:broadcast_chat, sender_guid, sender_name, channel, message, position}, state) do
  sender_session = find_session_by_guid(state, sender_guid)

  recipients =
    case channel do
      :say ->
        # Local chat - same zone instance only
        get_zone_sessions(state, sender_session.zone_id, sender_session.instance_id)

      :yell ->
        # Yell - same zone, all instances
        get_all_zone_sessions(state, sender_session.zone_id)

      :zone ->
        # Zone chat - same zone, all instances
        get_all_zone_sessions(state, sender_session.zone_id)

      :global ->
        # Global chat - everyone
        Map.values(state.sessions)

      _ ->
        []
    end

  for session <- recipients, session.entity_guid != sender_guid do
    send_chat_to_connection(session.connection_pid, sender_guid, sender_name, channel, message)
  end

  {:noreply, state}
end

defp get_zone_sessions(state, zone_id, instance_id) do
  account_ids = Map.get(state.zone_index, {zone_id, instance_id}, MapSet.new())
  for account_id <- account_ids, session = Map.get(state.sessions, account_id), do: session
end
```

**Benefit:** Say/yell only goes to same zone, reducing network traffic by 90%+ in busy servers.

---

## Implementation Order

| Order | Task | Phase | Dependencies |
|-------|------|-------|--------------|
| 1 | SpatialGrid module | 1.1 | None |
| 2 | Zone.Instance integration | 1.1 | SpatialGrid |
| 3 | WorldManager name index | 1.2 | None |
| 4 | Creature.ZoneManager | 1.3 | None |
| 5 | Session timestamps | 1.5 | None |
| 6 | EncryptedHandler | 1.4 | PacketCrypto |
| 7 | Handler registration | 2.1 | None |
| 8 | Inventory query fix | 2.2 | None |
| 9 | Promotion query fix | 2.3 | None |
| 10 | Database indexes | 2.4 | None |
| 11 | BuffManager sharding | 2.5 | Entity struct update |
| 12 | Handler middleware | 3.1 | None |
| 13 | Store pagination | 3.2 | None |
| 14 | Packet validation | 3.3 | None |
| 15 | Remove ProcessRegistry | 3.4 | Update all usages first |
| 16 | Protocol deviations doc | 3.5 | Research |
| 17 | Context module cleanup | 4.1 | None |
| 18 | World app reorganization | 4.2 | Handler middleware |
| 19 | ETS secondary indexes | 4.3 | None |
| 20 | Zone-based chat | 4.4 | WorldManager name index |

---

## Testing Strategy

1. **Unit Tests:** Each new module (SpatialGrid, Creature.ZoneManager) has comprehensive tests
2. **Integration Tests:** Handler tests verify end-to-end flow with new architecture
3. **Performance Tests:** Benchmark before/after for range queries and session lookups
4. **Load Tests:** Simulate 500+ entities per zone to verify sharding works

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Range query (500 entities) | ~5ms | <1ms |
| Session lookup by name | O(n) | O(1) |
| AI tick capacity | 100 creatures | 500+ per zone |
| Session hijacking window | Unlimited | 1 hour max |
| Protocol→World coupling | Compile-time | Runtime only |
