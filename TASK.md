# TASK.md - Code Review Findings

Last reviewed: 2025-12-18
Branch: feat/inventory-gear-system (68 commits ahead of origin)

## 🔴 Critical Priority

_No critical security vulnerabilities found._

## 🟠 High Priority

- [x] **[LOGGING]** ~~Remove excessive debug logging in `character_create_handler.ex`~~ (Fixed in e75179f)

- [x] **[LOGGING]** ~~Remove debug logging in `combat_broadcaster.ex:get_body_visuals/1`~~ (Fixed in e75179f)

- [ ] **[INCOMPLETE]** Item move slot decoding is incomplete
  - `item_move_handler.ex:124` has TODO: "Handle proper slot decoding for bags"
  - `decode_location/2` only handles equipped items correctly
  - Bag item moves may not work properly
  - File: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/item_move_handler.ex`

- [ ] **[RATE-LIMITING]** Protocol rate limiter not actually used
  - `BezgelorProtocol.RateLimiter` is defined and started in application supervisor
  - But no code actually calls it to limit auth attempts
  - File: `apps/bezgelor_protocol/lib/bezgelor_protocol/rate_limiter.ex`

## 🟡 Medium Priority

- [ ] **[DUPLICATION]** Two item move handlers with overlapping functionality
  - `item_move_handler.ex` (new, 195 lines) - handles ClientItemMove packets
  - `move_item_handler.ex` (existing, modified) - similar functionality
  - Consider consolidating into a single handler
  - Files: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/item_move_handler.ex`, `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/move_item_handler.ex`

- [ ] **[TESTING]** No tests for new item move handler
  - `ItemMoveHandler` has no corresponding test file
  - Critical inventory functionality should have unit tests
  - File: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/item_move_handler.ex`

- [ ] **[TESTING]** No tests for new visual update packet
  - `ServerEntityVisualUpdate` packet has no tests
  - File: `apps/bezgelor_protocol/lib/bezgelor_protocol/packets/world/server_entity_visual_update.ex`

- [ ] **[CONSISTENCY]** Mixed key access patterns in Store functions
  - Some functions check both string and atom keys: `Map.get(item, "key") || Map.get(item, :key)`
  - JSON is loaded with `keys: :atoms`, so string fallbacks are unnecessary
  - Files: `apps/bezgelor_data/lib/bezgelor_data/store.ex:1798-1802`, `1823`, `1872-1873`

- [ ] **[ERROR-HANDLING]** Silent failures in item move operations
  - `ItemMoveHandler.do_move/3` returns `{:ok, state}` on failures after logging
  - Client receives no feedback when move fails
  - Should send error response packet
  - File: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/item_move_handler.ex:69-71, 102-104`

## 🟢 Low Priority

- [ ] **[DOCS]** Add moduledoc to rate limiter modules
  - Both `BezgelorProtocol.RateLimiter` and `BezgelorPortal.Hammer` have minimal docs
  - Should document rate limits, cleanup intervals, and usage patterns
  - Files: `apps/bezgelor_protocol/lib/bezgelor_protocol/rate_limiter.ex`, `apps/bezgelor_portal/lib/bezgelor_portal/hammer.ex`

- [ ] **[CLEANUP]** Remove `require Logger` inside function
  - `combat_broadcaster.ex:593` has `require Logger` inside `get_body_visuals/1`
  - Should be at module level
  - File: `apps/bezgelor_world/lib/bezgelor_world/combat_broadcaster.ex:593`

- [ ] **[STYLE]** Inconsistent slot mapping constants
  - `item_move_handler.ex` defines `@equipped_to_item_slot` and `@visible_equipment_slots`
  - `move_item_handler.ex` defines similar mappings
  - Consider extracting to shared module
  - Files: `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/item_move_handler.ex:150-165`, `apps/bezgelor_protocol/lib/bezgelor_protocol/handler/move_item_handler.ex`

- [ ] **[GITIGNORE]** Add `.playwright-mcp/` to .gitignore
  - Playwright test state directory is untracked
  - Should be ignored to avoid accidental commits
  - File: `.gitignore`

---

## Completed Items

- [x] **[GITIGNORE]** Added proprietary game assets to .gitignore (portal_assets, m3_extractor test data)
- [x] **[FEAT]** Added `--local` flag to `mix assets.fetch` task

---

## Summary

**Total Issues: 12**
- 🔴 Critical: 0
- 🟠 High: 4
- 🟡 Medium: 5
- 🟢 Low: 4

**Key Recommendations:**
1. Clean up verbose logging before merging to main
2. Complete the bag slot decoding in ItemMoveHandler
3. Actually use the rate limiter in auth flow
4. Add tests for new inventory functionality
