# Code Review - December 15, 2025

## Overview

Comprehensive security and architecture review of the Bezgelor MMORPG server emulator. Focus areas: authentication, encryption, input validation, performance, and OTP patterns.

## Summary

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 4 | Addressing |
| High | 6 | Pending |
| Medium | 10 | Pending |
| Low | 5 | Pending |

## Critical Findings

### 1. Session Key Race Condition
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/world_auth_handler.ex:73-94`

**Issue:** Account ID validation occurs after session lookup with separate database query. Between `Accounts.validate_session_key()` and account ID comparison, a race condition exists where session key could be validated for wrong account.

**Fix:** Include account_id in the session validation query atomically in the database layer.

### 2. Plaintext Session Key Logging
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/connection.ex:279-308`

**Issue:** Session keys and encrypted packet contents logged in Base16 format at DEBUG level, exposing cryptographic material in logs.

**Fix:** Remove cryptographic material from all logs. Use truncated hashes for debugging if needed.

### 3. Missing Email Verification Enforcement
**File:** `apps/bezgelor_db/lib/bezgelor_db/accounts.ex:266-282`

**Issue:** `create_account()` doesn't enforce email verification, while `register_account()` does. Game clients may bypass email verification entirely.

**Fix:** Add email verification enforcement to `create_account()` or document intentional difference.

### 4. Hardcoded Encryption Build Number
**File:** `apps/bezgelor_crypto/lib/bezgelor_crypto/packet_crypt.ex:138-144`

**Issue:** Encryption keys derived from hardcoded client build number 16042. If client version changes, all packets become unencryptable.

**Fix:** Make build version configurable via application config.

## High Priority Findings

### 5. Missing Anti-Cheat Validation
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/movement_speed_update_handler.ex`

Players can set arbitrary movement speeds. No validation of maximum speed bounds, acceleration rates, or teleportation detection.

### 6. Insufficient Character Name Validation
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/character_create_handler.ex`

Character name validation mentioned in moduledoc but implementation unclear. Risk of injection attacks through character names.

### 7. Session Key TTL Too Long
**File:** `apps/bezgelor_db/lib/bezgelor_db/accounts.ex:161`

Session TTL of 1 hour is excessive. Compromised keys remain valid too long. Recommend 30 minutes with sliding window.

### 8. Unhandled Encryption Exceptions
**File:** `apps/bezgelor_crypto/lib/bezgelor_crypto/packet_crypt.ex:154-156`

`key_from_ticket()` raises ArgumentError on invalid input. Malformed packets crash connection handler.

### 9. Synchronous Zone Loading
**File:** `apps/bezgelor_world/lib/bezgelor_world/zone/manager.ex:42-79`

Zone initialization makes synchronous database calls. With 100+ zones, creates blocking boot sequence.

### 10. No Authentication Rate Limiting
**File:** `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/auth_handler.ex`

No rate limiting on failed authentication. Enables account enumeration and brute force attacks.

## Medium Priority Findings

- SQL injection via zone ID (zone/manager.ex)
- GenServer call deadlock risk (zone/instance.ex)
- Missing permission checks in item auctions
- Unvalidated customization data
- No transaction timeouts
- Incomplete broadcast implementation
- Undocumented ETS concurrency model
- No pagination limits enforcement
- Missing property-based tests
- No encryption round-trip tests

## Low Priority Findings

- Debug logs with crypto material in SRP6
- Magic numbers without constants
- Incomplete TODO handlers
- No persistence confirmation on logout
- Missing API documentation

## Action Plan

### Phase 1 - Critical (This Sprint)
1. Fix session key race condition
2. Remove crypto material from logs
3. Enforce email verification
4. Make build number configurable

### Phase 2 - High Priority (Next Sprint)
1. Add authentication rate limiting
2. Implement anti-cheat validation
3. Add character name validation
4. Reduce session TTL

### Phase 3 - Medium Priority
1. Add transaction timeouts
2. Implement broadcast
3. Add property-based tests

## References

- TASK.md contains full checklist
- NexusForever source at ../nexusforever/ for reference implementations
