# Protocol Deviations from NexusForever

This document tracks intentional differences between Bezgelor and the NexusForever C# implementation.

**Last Updated:** 2025-12-12

---

## Overview

Bezgelor is a WildStar server emulator written in Elixir, ported from NexusForever (C#). While we aim for protocol compatibility with the original WildStar client, there are intentional architectural and implementation differences.

---

## Packet Handling

### Opcode Numbering

Bezgelor uses the same opcode values as NexusForever for client compatibility. The complete mapping is in `apps/bezgelor_protocol/lib/bezgelor_protocol/opcode.ex`.

| Server | Port | Key Opcodes |
|--------|------|-------------|
| Auth (STS) | 6600 | 0x0003-0x0077 |
| Realm | 23115 | 0x0591-0x063D |
| World | 24000 | 0x0008+ |

**Notable Opcodes:**

| Opcode | Hex | Name | Purpose |
|--------|-----|------|---------|
| server_hello | 0x0003 | ServerHello | Initial server greeting |
| client_encrypted | 0x0077 | ClientEncrypted | Encrypted packet wrapper |
| client_hello_realm | 0x0008 | ClientHelloRealm | World server auth |
| client_movement | 0x07F4 | ClientMovement | Player position updates |

### Modified Packet Structures

| Packet | Field | Bezgelor Difference | Reason |
|--------|-------|---------------------|--------|
| - | - | None currently | - |

**Note:** Packet structures aim to match NexusForever exactly. Any deviations discovered during testing should be documented here.

### Handler Registration

**NexusForever:** Handlers are discovered via reflection and registered at compile time.

**Bezgelor:** Handlers are registered at runtime during application startup via `BezgelorWorld.HandlerRegistration.register_all/0`. This decouples the protocol layer from the world layer.

```elixir
# apps/bezgelor_world/lib/bezgelor_world/handler_registration.ex
def register_all do
  PacketRegistry.register(:client_chat, ChatHandler)
  PacketRegistry.register(:client_cast_spell, SpellHandler)
  # ...
end
```

---

## Authentication

### SRP6 Implementation

Both implementations use WildStar's SRP6 variant with these parameters:

| Parameter | Value |
|-----------|-------|
| Prime (N) | 1024-bit safe prime |
| Generator (g) | 2 |
| Hash | SHA256 |

**Key Differences:**

| Aspect | NexusForever | Bezgelor | Notes |
|--------|--------------|----------|-------|
| Language | C# BigInteger | Elixir :crypto | Functionally equivalent |
| Byte ordering | Manual handling | :binary module | Elixir-native approach |
| Session storage | In-memory | ETS table | Better concurrency |

**Implementation:** `apps/bezgelor_crypto/lib/bezgelor_crypto/srp6.ex`

### Session Key Handling

**NexusForever:** Session keys stored in session manager with no TTL.

**Bezgelor:** Session keys stored in ETS with TTL (default 1 hour):

```elixir
# Session stored with expiration
%{
  account_id: account_id,
  session_key: session_key,
  created_at: System.system_time(:second),
  expires_at: System.system_time(:second) + 3600
}
```

Expired sessions are cleaned up automatically by `BezgelorAuth.SessionCleaner`.

### Packet Encryption

The XOR-based packet cipher is implemented identically to NexusForever:

| Aspect | Value |
|--------|-------|
| Key size | 1024-bit (128 bytes) |
| Multiplier | 0xAA7F8EA9 |
| Initial value | 0x718DA9074F2DEB91 |
| Build hardcoded | 16042 |

**Implementation:** `apps/bezgelor_crypto/lib/bezgelor_crypto/packet_crypt.ex`

---

## Game Logic Differences

### Combat Calculations

| Calculation | NexusForever | Bezgelor | Notes |
|-------------|--------------|----------|-------|
| Damage formula | Same | Same | Direct port |
| Miss/hit/crit | Same | Same | Direct port |
| Stat scaling | Same | Same | Direct port |

**Implementation:** `apps/bezgelor_core/lib/bezgelor_core/combat.ex`

### Entity Management

**NexusForever:** Single-threaded entity management in world server.

**Bezgelor:** Multi-process architecture:
- One GenServer per zone instance
- Per-zone creature managers for AI
- Spatial grid for O(k) range queries vs O(n)

### Buff Management

**NexusForever:** Central buff manager.

**Bezgelor:** Sharded buff management:
- Buffs stored on Entity struct
- BuffManager shards by entity GUID hash
- Better horizontal scaling

---

## Architectural Differences

### Process Model

| Aspect | NexusForever | Bezgelor |
|--------|--------------|----------|
| Concurrency | Thread pool | Actor model (OTP) |
| State isolation | Shared state + locks | Message passing |
| Fault tolerance | Manual | Supervision trees |
| Connection handling | Thread per connection | Process per connection |

### Data Storage

| Data Type | NexusForever | Bezgelor |
|-----------|--------------|----------|
| Static game data | In-memory dictionaries | ETS tables |
| Player state | Database + cache | Database + GenServer |
| Session state | Session manager | ETS + GenServer |

### Database Access

| Aspect | NexusForever | Bezgelor |
|--------|--------------|----------|
| ORM | Entity Framework | Ecto |
| Queries | LINQ | Ecto.Query |
| Transactions | Manual | Ecto.Multi |
| Connection pooling | ADO.NET | DBConnection |

---

## Known Incompatibilities

### Client Version Support

| Client Version | Build | Status |
|----------------|-------|--------|
| Final NA/EU | 16042 | Primary target |
| Korean | Various | Untested |
| China | Various | Untested |

### Features Requiring Client Patches

None currently known. The emulator targets unmodified retail client.

---

## Verification Status

Items verified against original client:

- [x] Basic authentication flow (SRP6)
- [x] Packet encryption/decryption
- [x] Character creation/selection
- [x] World entry
- [x] Movement synchronization
- [x] Chat messaging
- [x] Spell casting
- [ ] Complex combat scenarios
- [ ] Housing system
- [ ] Dungeon instances
- [ ] PvP systems
- [ ] Warplots

Items requiring further verification:

| Feature | Status | Notes |
|---------|--------|-------|
| Encrypted packet inner dispatch | Implemented | Needs client testing |
| Entity interpolation | Basic | May need tuning |
| Spell telegraph sync | Partial | Client-specific timing |
| Guild bank | Implemented | Untested |
| Mail attachments | Implemented | Untested |

---

## Contributing

When implementing new features:

1. Reference NexusForever source for packet structures
2. Test against actual WildStar client
3. Document any intentional deviations here
4. Note incompatibilities or workarounds

### Adding a Deviation Entry

```markdown
### Feature Name

**NexusForever:** [describe C# implementation]

**Bezgelor:** [describe Elixir implementation]

**Reason:** [why the deviation exists]

**Impact:** [client compatibility notes]
```

---

## References

- [NexusForever GitHub](https://github.com/NexusForever/NexusForever)
- [WildStar Protocol Documentation](https://github.com/NexusForever/NexusForever/wiki)
- [SRP6 RFC 2945](https://tools.ietf.org/html/rfc2945)
