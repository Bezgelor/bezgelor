# Bezgelor Playability Gap Analysis

**Date:** 2025-12-12
**Status:** Assessment Complete

## Executive Summary

Bezgelor is a **feature-complete game engine with minimal game content**. The architecture is excellent—far better organized than NexusForever thanks to Elixir/OTP—but without quest content and populated zones, it's currently a tech demo rather than a playable game.

| Aspect | Status |
|--------|--------|
| Systems Implementation | ~95% complete |
| Content/Data | ~5% complete |
| Playable Zones | 1 of 3,436 |
| Quests Defined | 0 |
| Dungeons Working | 0 of 46 |

---

## Comparison: Bezgelor vs NexusForever

| Aspect | Bezgelor | NexusForever |
|--------|----------|--------------|
| **Language** | Elixir/OTP | C# |
| **Architecture** | Excellent (umbrella app, supervision trees) | Good (monolithic) |
| **Systems** | ~95% complete | ~80% complete |
| **Content** | ~5% complete | ~15% complete |
| **Playable Zones** | 1 (Celestion) | Most open world |
| **Quests** | 0 defined | "Major thing lacking" |
| **Dungeons** | Framework only | 1 of 46 playable |
| **Can Progress** | No | Barely |

Both projects share the same fundamental problem: **systems without content**.

---

## Current Content Inventory

### What Exists

| Category | Data Files | Records | Status |
|----------|------------|---------|--------|
| Zones | `zones.json` | 3,436 | ✅ Definitions complete |
| Creatures | `creatures.json` (21MB) | 53,137 | ✅ Templates complete |
| Items | `items.json` (37MB) | 71,918 | ✅ Definitions complete |
| Texts | `texts.json` (31MB) | Full i18n | ✅ Localization complete |
| Creature Spawns | `creature_spawns.json` | 5,091 | ⚠️ Only 1 zone |
| Tradeskills | Multiple files | Complete | ✅ Full system |
| Battlegrounds | `battlegrounds.json` | 2 | ⚠️ Limited |
| Arenas | `arenas.json` | Configured | ⚠️ Limited |
| Instances | `instances.json` | Framework | ⚠️ Minimal content |

### What's Missing

| Category | Status | Impact |
|----------|--------|--------|
| **Quest Definitions** | 0 quests | Cannot progress |
| **NPC/Vendor Data** | No NPC layer | Cannot buy/sell |
| **Zone Population** | 99% empty | Dead world |
| **Loot Tables** | Unassigned | No rewards |
| **Gathering Nodes** | 0 spawns | Tradeskills broken |
| **Dungeon Scripts** | 1 example | No PvE endgame |
| **Dialogue Trees** | None | NPCs are silent |

---

## Detailed Gap Analysis

### 1. Quest System (CRITICAL - 0% Content)

**What exists:**
- Database schemas: `Quest`, `QuestHistory` with full lifecycle
- Protocol packets: Accept, abandon, turn-in implemented
- Handler: `QuestHandler` in world server
- Progress tracking: JSON-based objective progress

**What's missing:**
- Zero quest definitions in any data file
- No quest templates with objectives, rewards, prerequisites
- No quest giver assignments
- No quest chains or story progression
- No dialogue content

**Impact:** Players cannot progress beyond initial spawn.

### 2. NPC/Vendor System (CRITICAL - 0% Content)

**What exists:**
- 53,137 creature templates
- Creature spawn system

**What's missing:**
- No NPC type designation (vendor, quest giver, trainer)
- No vendor inventory assignments
- No dialogue/interaction system
- No faction merchant data

**Impact:** Players cannot buy, sell, or interact meaningfully.

### 3. World Population (CRITICAL - 1% Complete)

**What exists:**
- 3,436 zone definitions with full metadata
- 5,091 creature spawns (Celestion only)
- 309 object spawns

**What's missing:**
- 3,433 zones have zero creature spawns
- Zero resource/gathering node spawns
- No dungeon layouts

**Impact:** 99% of the world is empty.

### 4. Loot System (30% Complete)

**What exists:**
- Loot generation framework
- Event loot tables (minimal)
- Item database (71,918 items)

**What's missing:**
- Creature → loot table mappings
- Boss-specific drops
- Chest/container loot
- Zone-appropriate loot scaling

**Impact:** Killing creatures provides no meaningful rewards.

### 5. Dungeon/Instance Content (5% Complete)

**What exists:**
- Full instance framework (lifecycle, lockouts, roles)
- Boss encounter DSL with phases, telegraphs, mechanics
- Mythic+ system with keystones and affixes
- One example boss (Stormtalon)

**What's missing:**
- Comprehensive boss scripts (45+ dungeons)
- Raid encounter content
- Dungeon waypoint/layout data

**Impact:** No PvE endgame content.

### 6. Tradeskill Content (70% Complete)

**What exists:**
- 6 crafting + 3 gathering professions
- Schematics, talents, additives
- Coordinate-based crafting system
- Work order templates

**What's missing:**
- Gathering node world positions
- Node spawn data per zone

**Impact:** Gathering professions non-functional.

---

## Gap Inventory (Ranked by Priority)

### Tier 1: Required for Basic Playability

| # | Gap | Impact | Effort | Data Source |
|---|-----|--------|--------|-------------|
| 1 | **Quest Content** | Cannot progress | High | Extract from client or manual |
| 2 | **NPC/Vendor System** | Cannot interact | Medium | Build new layer |
| 3 | **Zone Population** | Empty world | Medium | NexusForever.WorldDatabase |

### Tier 2: Required for Meaningful Gameplay

| # | Gap | Impact | Effort | Data Source |
|---|-----|--------|--------|-------------|
| 4 | **Loot Table Assignment** | No rewards | Medium | Algorithmic + manual |
| 5 | **Gathering Node Spawns** | Tradeskills broken | Medium | Extract or generate |
| 6 | **Dungeon Encounters** | No PvE endgame | High | Manual scripting |

### Tier 3: Polish & Completeness

| # | Gap | Impact | Effort | Data Source |
|---|-----|--------|--------|-------------|
| 7 | **Dialogue System** | NPCs silent | Medium | Extract from client |
| 8 | **Achievement Triggers** | No progress sense | Medium | Wire to existing system |
| 9 | **Path Mission Content** | Paths empty | Medium | Need mission definitions |
| 10 | **Additional Battlegrounds** | Limited PvP | Medium | Manual creation |

---

## Recommended Implementation Path

### Phase A: World Population (Weeks 1-2)

**A.1: Import NexusForever.WorldDatabase**
```
Source: https://github.com/NexusForever/NexusForever.WorldDatabase
Content: 49 SQL files with creature spawn positions
Format: SQL → JSON → ETS loader
Result: All zones populated with creatures
```

**A.2: Build NPC Layer**
- Add `npc_type` enum to creature system
- Create `vendor_inventory` table
- Wire into existing spawn system

**A.3: Basic Loot Tables**
- Map creature difficulty → item quality
- Generate procedural tables by zone level
- Add boss-specific overrides

### Phase B: Quest Foundation (Weeks 3-4)

**B.1: Quest Data Extraction**

Options (in order of preference):
1. Extract from WildStar client `.tbl` files
2. Port partial data from NexusForever
3. Manual creation of starter quests

**B.2: Create Starter Content**
- 20 quests for level 1-10 (tutorial zone)
- Basic kill, collect, explore objectives
- Wire to existing quest system

### Phase C: Extended Progression (Weeks 5-8)

**C.1: Additional Quests**
- 50+ quests for level 10-20
- Quest chains with story
- Zone transition quests

**C.2: Gathering Nodes**
- Extract or generate node positions
- Distribute by zone type and level

**C.3: First Dungeon**
- Script Stormtalon's Lair completely
- All boss mechanics
- Loot tables

### Phase D: Endgame (Ongoing)

- Script additional dungeons (priority order)
- Raid content
- Extended battleground maps

---

## Effort Estimates

| Task | Complexity | Time Estimate |
|------|------------|---------------|
| WorldDatabase import | Medium | 1-2 days |
| NPC/Vendor system | Medium | 2-3 days |
| 20 starter quests | High | 1 week |
| Loot table wiring | Medium | 2-3 days |
| Gathering nodes | Medium | 1-2 days |
| First dungeon complete | High | 1 week |
| 50 additional quests | High | 2-3 weeks |

**Minimum viable "playable" (level 1-20):** 3-4 weeks focused work

---

## Data Sources

### NexusForever.WorldDatabase
- **URL:** https://github.com/NexusForever/NexusForever.WorldDatabase
- **Content:** Creature spawn positions by zone
- **Format:** SQL files organized by continent
- **Status:** Issue created for import

### WildStar Client Data
- **Tool:** `tools/tbl_extractor/`
- **Potential:** Quest definitions, NPC data, loot tables
- **Status:** Needs investigation

### Community Resources
- **Jabbithole:** Item/quest database (archived)
- **WildStar Wiki:** Quest walkthroughs, NPC locations
- **Status:** Manual extraction possible

---

## Related Documents

- [Account Portal Design](plans/2025_12_12_account_portal_design.md)
- [Account Portal Implementation](plans/2025_12_12_account_portal_implementation.md)
- [World Database Import Issue](issues/world_database_import.md)
- [Project Status](status.md)

---

## Conclusion

Bezgelor represents an impressive technical achievement—a complete WildStar server architecture in Elixir with excellent code organization and comprehensive system implementations. However, the project currently functions as a **combat sandbox** rather than a playable game.

The path to playability is clear:
1. Populate the world (WorldDatabase import)
2. Enable basic interactions (NPC/vendor layer)
3. Create progression (quest content)

With focused effort, a playable level 1-20 experience is achievable in 3-4 weeks. Full game parity with live WildStar would require significantly more content creation effort, likely measured in months of work.

The architectural foundation is solid. What remains is content population—a task that can be parallelized and potentially crowdsourced once the data pipeline infrastructure is in place.
