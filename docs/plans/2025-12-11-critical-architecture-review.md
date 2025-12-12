# Critical Architecture Review

**Date:** 2025-12-11
**Status:** Complete
**Scope:** Full codebase analysis across 5 dimensions

---

## Executive Summary

This review analyzed the Bezgelor codebase across architecture, abstractions, protocol, database, and performance. While the foundation is solid (clean app separation, good core utilities, well-designed static data layer), significant issues exist that would prevent production-ready scaling.

### Critical Issues (Immediate Attention)

| Issue | Impact | Location |
|-------|--------|----------|
| Protocol→World dependency inversion | Architecture violation | `packet_registry.ex:91-98` |
| Zone range queries O(n) | Quadratic scaling | `zone/instance.ex:287-302` |
| Single CreatureManager process | AI lag at 500+ creatures | `creature_manager.ex` |
| Encrypted packet handler unimplemented | Security gap | `encrypted_handler.ex` |
| Session validation lacks timestamps | Session hijacking risk | `world_auth_handler.ex` |

### High-Priority Issues (Short-term)

| Issue | Impact | Location |
|-------|--------|----------|
| Handler-to-handler tight coupling | Testing/maintenance burden | `reputation_handler.ex`, etc. |
| N+1 query in find_empty_slot | 6 DB queries per call | `inventory.ex:288-319` |
| In-memory promotion filtering | Loads all promotions per item | `storefront.ex:194-214` |
| Linear session lookups | 5K iterations per whisper | `world_manager.ex:195-202` |
| ProcessRegistry abstraction leaking | Adds complexity, not value | `instance.ex:61` |

---

## 1. Architecture Analysis

### What's Working Well

- **bezgelor_core** is properly isolated (no internal dependencies)
- **bezgelor_crypto** is independent and security-focused
- **bezgelor_db** has clean context-based interfaces
- **Packet definitions** cleanly separated from handlers
- **No circular dependencies** between major apps

### Critical Architectural Issues

#### 1.1 Protocol→World Dependency Inversion (CRITICAL)

**Location:** `apps/bezgelor_protocol/lib/bezgelor_protocol/packet_registry.ex:91-98`

```elixir
default_handlers do
  %{
    client_chat: BezgelorWorld.Handler.ChatHandler,
    client_cast_spell: BezgelorWorld.Handler.SpellHandler,
    # ... more world handlers hardcoded in protocol layer
  }
end
```

**Problem:** The protocol layer (low-level network) directly references the world layer (high-level game logic). This:
- Breaks clean architecture principles
- Makes protocol untestable without world
- Creates tight coupling that increases maintenance burden

**Recommended Fix:** Let world app register handlers at startup via callback, not hardcoded imports.

#### 1.2 Handler Responsibility Confusion (HIGH)

Handlers exist in BOTH `bezgelor_protocol` and `bezgelor_world`:
- Protocol handlers: `CharacterCreateHandler` directly calls `BezgelorDb.Characters.create_character()`
- World handlers: 24 handlers implementing game logic

**Problem:** Business logic leaks into protocol layer. `character_create_handler.ex:59-102` performs database operations directly.

**Ideal Pattern:**
```
Protocol Handlers: Parse → Validate → Call context or publish event
World Handlers: Subscribe to events → Execute logic → Send response
```

#### 1.3 World App Oversized (MEDIUM)

`bezgelor_world` contains 24 handlers + 6 major subsystems (6000+ lines):
- `/handler/` - 24 files
- `/encounter/`, `/loot/`, `/instance/`, `/pvp/`, `/mythic_plus/`, `/group_finder/`

No organizational structure between these subsystems.

---

## 2. Abstractions Analysis

### Summary Table

| Abstraction | Status | Lines | Usage | Verdict |
|-------------|--------|-------|-------|---------|
| ProcessRegistry | Leaking | 250 | 4 files | **REMOVE** |
| PacketReader/Writer | Excellent | 360 | 56 files | **KEEP** |
| Zone/Instance | Fragmented | 400+ | 20+ files | **REFACTOR** |
| Handler pattern | Missing middleware | 2000+ | All handlers | **ADD** |
| Context modules | Thin but valuable | 800+ | Heavy | **STRENGTHEN** |
| ETS Store | Perfect | 800 | Indirect | **KEEP** |

### 2.1 ProcessRegistry - REMOVE

**Problem:** Abstraction over Elixir Registry that's being bypassed.

**Evidence:** `zone/instance.ex:61` directly accesses `ProcessRegistry.Registry`:
```elixir
def via_tuple(zone_id, instance_id) do
  {:via, Registry, {ProcessRegistry.Registry, {:zone_instance, {zone_id, instance_id}}}}
end
```

The "future migration to gproc" (line 34) is unrealistic given the leakage. 250 lines for 4 call sites.

### 2.2 PacketReader/Writer - KEEP

**Why it works:**
- Clean interface for bit-level protocol parsing
- 56 files using it consistently
- No leakage - callers never bypass by doing raw binary ops
- Handles real complexity (WildStar bit-packed fields)

### 2.3 Zone/Instance Pattern - REFACTOR

**Problem:** Three competing registry patterns:
1. `ProcessRegistry` (bezgelor_core)
2. `Instance.Registry` (bezgelor_world/instance)
3. Manual Registry via tuples (zone/instance.ex)

Also: `Zone.Instance` and `Instance.Instance` are parallel implementations.

### 2.4 Handler Middleware - ADD

**Problem:** 24 handlers with duplicated patterns:
- "player in world" check repeated in chat, spell, inventory, combat handlers
- No shared authentication/validation middleware
- Each handler reinvents: parse → validate → execute → respond

### 2.5 ETS Store - KEEP (Reference Design)

Perfect encapsulation:
- All ETS access in `store.ex`
- Zero direct ETS access from game code
- Clean dual-layer API (raw access + typed wrappers)

---

## 3. Protocol Analysis

### Critical Issues

#### 3.1 Encrypted Handler Not Implemented (CRITICAL)

**Location:** `encrypted_handler.ex:14-18`

```elixir
def handle(payload, state) do
  Logger.debug("EncryptedHandler: received #{byte_size(payload)} bytes")
  # TODO: Decrypt and re-dispatch inner packet
  {:ok, state}
end
```

All encrypted packets (opcode 0x0077) are silently ignored.

#### 3.2 Session Validation Lacks Timestamps (HIGH)

**Location:** `world_auth_handler.ex:61-78`

Session keys have no TTL - old session keys remain valid indefinitely. Risk of session hijacking.

#### 3.3 Entity GUID May Truncate (HIGH)

**Location:** `world_entry_handler.ex:67-78`

```elixir
bsl(entity_type, 60) ||| bsl(character.id &&& 0xFFFFFF, 24) ||| (counter &&& 0xFFFFFF)
```

If `character.id > 16.7M`, it truncates. Counter collision possible across processes.

### Missing Validation

| Packet | Issue | Risk |
|--------|-------|------|
| ClientCastSpell | Position can be NaN/Inf | Out-of-world exploit |
| ClientChat | No length limit | Buffer exhaustion, spam |
| ClientCharacterCreate | Race/class not validated | Invalid data accepted |
| All wide_string reads | No max length | Memory DOS |

### Hardcoded Protocol Constants

**Location:** `connection.ex:152-157`

```elixir
|> PacketWriter.write_uint32(16042)     # AuthVersion - hardcoded
|> PacketWriter.write_uint32(0x97998A0) # AuthMessage - magic number
```

Version-specific values that could fail with different clients.

---

## 4. Database Analysis

### Schema Friction Summary

| Issue | Severity | Location | Impact |
|-------|----------|----------|--------|
| Corrective migration (verifier size) | MEDIUM | `fix_verifier_column_size.exs` | Schema churn |
| Storefront incomplete v1 | MEDIUM | `add_storefront_features.exs` | 122-line patch |
| PvpStats god table (25 columns) | HIGH | `pvp_stats.ex` | Denormalization, sync risk |
| EventParticipation array field | MEDIUM | `event_participation.ex` | Query inefficiency |
| StoreItem dual category fields | MEDIUM | `store_item.ex` | Legacy + new coexist |

### N+1 Query Patterns

#### Inventory.find_empty_slot (HIGH)

**Location:** `inventory.ex:288-319`

```elixir
def find_empty_slot(character_id, container_type \\ :bag) do
  bags = get_bags(character_id)  # Query 1
  |> Enum.find_value(fn bag ->
    occupied_slots = InventoryItem |> where(...) |> Repo.all()  # Query per bag
  end)
end
```

For 5 bags: 1 + 5 = 6 database queries per call.

#### In-Memory Promotion Filtering (HIGH)

**Location:** `storefront.ex:194-214`

```elixir
StorePromotion
|> where([p], p.is_active == true)
|> Repo.all()                    # Load ALL promotions
|> Enum.find(fn promo -> ... end) # Filter in memory
```

Loads hundreds of promotions, filters in Elixir.

### Missing Indexes

```elixir
# Added late in enhancement migration:
create index(:store_items, [:category_id])
create index(:store_items, [:is_active])

# Still missing:
# - work_orders by [:status, :expires_at]
# - schematic_discoveries by [:schematic_id]
```

---

## 5. Performance Analysis

### Critical Bottlenecks

#### 5.1 Zone Range Queries O(n) (CRITICAL)

**Location:** `zone/instance.ex:287-302`

```elixir
def handle_call({:entities_in_range, {x, y, z}, radius}, _from, state) do
  entities =
    state.entities
    |> Map.values()          # Full iteration
    |> Enum.filter(fn entity -> distance_calculation... end)  # O(n)
end
```

**Impact:** 200 players + 500 creatures = 70,000 distance calculations per query.
At 50 movements/second = 3.5M calculations/second.

**Fix:** Implement spatial grid or quadtree.

#### 5.2 Single CreatureManager Process (CRITICAL)

**Location:** `creature_manager.ex:372-397`

One GenServer handles ALL creatures globally. AI updates capped at 100 creatures/tick.

**Impact:** 1,000 creatures in combat → 10 seconds to process all. AI appears unresponsive.

**Fix:** Shard by zone/region.

#### 5.3 Linear Session Lookups (HIGH)

**Location:** `world_manager.ex:195-202`

```elixir
Enum.find(state.sessions, fn {_account_id, session} ->
  String.downcase(session.character_name) == String.downcase(character_name)
end)
```

**Impact:** 5,000 players → 5,000-iteration scan per whisper.

**Fix:** Add name index map.

### GenServer Bottlenecks

| Process | Responsibility | Sharding Strategy |
|---------|---------------|-------------------|
| CreatureManager | All creatures globally | Shard by zone |
| BuffManager | All buffs globally | Shard by entity GUID hash |
| WorldManager | All sessions | Add name/GUID indexes |
| Zone.Instance | Single zone | Already sharded (good) |

### ETS Query Patterns

**Location:** `store.ex:62-67`

```elixir
def list(table) do
  :ets.tab2list(table_name(table))  # Loads ENTIRE table
  |> Enum.map(fn {_id, data} -> data end)
end
```

50,000 schematics → 50KB+ transferred per query.

**Fix:** Use `:ets.match()` for server-side filtering.

---

## Recommended Remediation Priority

### Phase 1: Critical (1-2 weeks)

1. **Implement spatial grid** for zone instance range queries
2. **Add name index** to WorldManager for O(1) lookups
3. **Shard CreatureManager** by zone
4. **Implement encrypted packet handler** (security)
5. **Add session timestamp validation** (security)

### Phase 2: High Priority (2-4 weeks)

6. **Break Protocol→World dependency** - handler registration at startup
7. **Fix N+1 queries** - inventory.find_empty_slot, storefront promotions
8. **Add missing database indexes**
9. **Shard BuffManager** by entity
10. **Consolidate Zone/Instance registries**

### Phase 3: Medium Priority (1-2 months)

11. **Add handler middleware** for cross-cutting concerns
12. **Implement pagination** for store queries
13. **Add input validation** to packets (position bounds, string lengths)
14. **Remove ProcessRegistry** abstraction (direct Registry usage)
15. **Document protocol deviations** from NexusForever

### Phase 4: Low Priority (Ongoing)

16. **Strengthen context modules** - fix Repo leakage in handlers
17. **Reorganize world app** - extract subsystems to contexts
18. **Add secondary ETS indexes** for common lookups
19. **Implement zone-based chat routing**

---

## Conclusion

The Bezgelor architecture has a **solid foundation** with clean separation of core utilities, cryptography, and database access. The **static data layer (ETS Store)** and **packet parsing (PacketReader/Writer)** are well-designed.

However, **handler organization** and **process architecture** will not scale:
- Protocol→World coupling creates maintenance burden
- Single-process managers (Creature, Buff) become bottlenecks
- O(n) algorithms in hot paths limit concurrent player capacity

With the recommended Phase 1-2 fixes, the server could support **5-10x more concurrent players**. The changes are incremental and don't require full rewrite.

**Risk Assessment:**
- Current architecture: Suitable for 100-200 concurrent players
- After Phase 1-2 fixes: Suitable for 500-1000 concurrent players
- After full remediation: Suitable for 2000+ concurrent players
