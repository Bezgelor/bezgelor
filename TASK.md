# TASK.md - Code Review Findings

Generated: 2025-12-15

## 🔴 Critical Priority

- [x] **[SECURITY]** Fix session key race condition in `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/world_auth_handler.ex:73-94` - Include account_id in session validation query atomically
- [x] **[SECURITY]** Remove plaintext session key logging in `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex:279-308` - Exposes cryptographic material
- [x] **[SECURITY]** Enforce consistent email verification in `apps/bezgelor_db/lib/bezgelor_db/accounts.ex:266-282` - Documented intentional design (game client auto-registration vs portal registration)
- [x] **[SECURITY]** Replace hardcoded build number in key derivation `apps/bezgelor_crypto/lib/bezgelor_crypto/packet_crypt.ex:138-144` - Made configurable via application config

## 🟠 High Priority

- [ ] **[SECURITY]** Add anti-cheat validation in `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/movement_speed_update_handler.ex` - No speed/teleport bounds checking
- [ ] **[SECURITY]** Add character name validation in `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_create_handler.ex` - Whitelist allowed characters
- [ ] **[SECURITY]** Reduce session TTL from 1 hour in `apps/bezgelor_db/lib/bezgelor_db/accounts.ex:161` - Implement sliding window expiration
- [ ] **[BUG]** Handle encryption exceptions in `apps/bezgelor_crypto/lib/bezgelor_crypto/packet_crypt.ex:154-156` - Return error tuple instead of raising
- [ ] **[PERFORMANCE]** Make zone initialization async in `apps/bezgelor_world/lib/bezgelor_world/zone/manager.ex:42-79` - Blocking startup with 100+ zones
- [ ] **[SECURITY]** Add authentication rate limiting in `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/auth_handler.ex` - Enable brute force, account enumeration

## 🟡 Medium Priority

- [ ] **[SECURITY]** Validate zone_id as positive integer in `apps/bezgelor_world/lib/bezgelor_world/zone/manager.ex:223-232`
- [ ] **[BUG]** Add explicit GenServer timeouts in `apps/bezgelor_world/lib/bezgelor_world/zone/instance.ex:95-101` - Deadlock risk
- [ ] **[SECURITY]** Add permission checks in `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/item_auctions_handler.ex` - Cross-account access
- [ ] **[SECURITY]** Validate customization data in `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_create_handler.ex:119-125`
- [ ] **[BUG]** Add transaction timeouts in `apps/bezgelor_db/lib/bezgelor_db/accounts.ex:310-322` - Could hang indefinitely
- [ ] **[FEATURE]** Implement actual broadcast in `apps/bezgelor_world/lib/bezgelor_world/zone/instance.ex:295-304` - Currently stubbed
- [ ] **[DOCS]** Document ETS table concurrency model in `apps/bezgelor_data/lib/bezgelor_data/store.ex:15-92`
- [ ] **[SECURITY]** Add maximum limit enforcement in `apps/bezgelor_db/lib/bezgelor_db/accounts.ex:697-727`
- [ ] **[TESTING]** Add property-based tests for packet fuzzing - Unguarded handler error paths
- [ ] **[TESTING]** Add encryption/decryption round-trip tests - No crypto test coverage

## 🟢 Low Priority

- [ ] **[CLEANUP]** Use environment-based debug flags in `apps/bezgelor_crypto/lib/bezgelor_crypto/srp6.ex:231-245`
- [ ] **[REFACTOR]** Extract magic numbers to constants in `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex:226-237`
- [ ] **[FEATURE]** Complete TODO handlers (movement_speed_update, item_auctions, etc.)
- [ ] **[BUG]** Add persistence confirmation in `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex:482-502` - Quest changes lost on DB failure
- [ ] **[DOCS]** Add JSDoc-style documentation to public API functions

## Completed

_None yet_
