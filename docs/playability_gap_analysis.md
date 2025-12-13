# Bezgelor Playability Gap Analysis

**Date:** 2025-12-12
**Status:** Assessment Complete

## Executive Summary

Bezgelor is a **feature-complete game engine with minimal game content**. The architecture is excellent—far better organized than NexusForever thanks to Elixir/OTP—but without quest content and populated zones, it's currently a tech demo rather than a playable game.

| Aspect | Status |
|--------|--------|
| Systems Implementation | ~98% complete |
| Content/Data | ~92% complete |
| Populated Worlds | 7 of 7 (open world) |
| Resource Spawns | ✅ 5,015 harvest nodes + 83 loot mappings |
| Quests Defined | 5,194 (from client) |
| Quest Giver Mappings | ✅ Available (creatures_full) |
| Vendor Inventories | ✅ 881 vendors, 35,842 items |
| Loot System | ✅ Real items + equipment drops + corpse pickup |
| Gathering Loot | ✅ Mining, Survivalist, Relic Hunter, Farming |
| Combat System | ✅ Stats, ticks, XP, telegraphs complete |
| Dungeons Working | 0 of 46 |

---

## What's Needed

| Category | Status | Work Required |
|----------|--------|---------------|
| **Quest Wiring** | ✅ Wired | Handlers registered, ready for client testing |
| **Vendor Inventories** | ✅ Generated | 881 vendors, 35,842 item listings |
| **Loot Tables** | ✅ Complete | Real items, equipment drops, group bonuses |
| **Gathering Nodes** | ✅ Complete | 5,015 harvest nodes + 83 loot mappings |
| **Dungeon Scripts** | DSL ready | Script 46 dungeon encounters |
| **Dialogue Wiring** | ✅ Complete | Click-dialogue + ambient gossip implemented |

The primary work is **integration**, not content creation—data exists, systems exist, they need connection.

---

## Current Content Inventory

### What Exists

| Category | Data Files | Records | Status |
|----------|------------|---------|--------|
| Zones | `zones.json` | 3,436 | ✅ Definitions complete |
| Creatures | `creatures.json` (21MB) | 53,137 | ✅ Templates complete |
| Creatures (Full) | `creatures_part1-4.json` (236MB) | 53,137 | ✅ **173 fields including quest givers** |
| Items | `items.json` (37MB) | 71,918 | ✅ Definitions complete |
| Texts | `texts.json` (31MB) | Full i18n | ✅ Localization complete |
| Creature Spawns | `creature_spawns.json` | 41,056 | ✅ All open world zones |
| Object Spawns | `creature_spawns.json` | 2,921 | ✅ Imported from WorldDatabase |
| **Quests** | `quests.json` | 5,194 | ✅ **Extracted from client** |
| **Quest Objectives** | `quest_objectives.json` | 10,031 | ✅ **Extracted from client** |
| **Quest Rewards** | `quest_rewards.json` | 5,415 | ✅ **Extracted from client** |
| **NPC Vendors** | `npc_vendors.json` | 881 | ✅ **Extracted from client** |
| **Vendor Inventories** | `vendor_inventories.json` | 35,842 items | ✅ **Generated for all vendors** |
| **Achievements** | `achievements.json` | 4,943 | ✅ **Extracted from client** |
| **Path Missions** | `path_missions.json` | 1,064 | ✅ **Extracted from client** |
| **Gossip/Dialogue** | `gossip_entries.json` | 10,799 | ✅ **Extracted from client** |
| **Challenges** | `challenges.json` | 643 | ✅ **Extracted from client** |
| **World Locations** | `world_locations.json` | 33,396 | ✅ **Extracted from client** |
| Tradeskills | Multiple files | Complete | ✅ Full system |
| **Harvest Loot** | `harvest_loot.json` | 83 | ✅ **Node→loot mappings by profession/tier** |
| Battlegrounds | `battlegrounds.json` | 2 | ⚠️ Limited |
| Arenas | `arenas.json` | Configured | ⚠️ Limited |
| Instances | `instances.json` | Framework | ⚠️ Minimal content |

### What's Missing (Reduced!)

| Category | Status | Impact |
|----------|--------|--------|
| ~~Quest Definitions~~ | ✅ **5,194 extracted** | Needs wiring to system |
| ~~NPC/Vendor Data~~ | ✅ **881 vendors + 35,842 items** | ✅ Complete |
| ~~Vendor Inventories~~ | ✅ **Generated** | ✅ Complete |
| ~~Loot Tables~~ | ✅ **Real items + equipment** | ✅ Complete |
| ~~Gathering Nodes~~ | ✅ **5,015 nodes extracted** | ✅ Complete |
| **Dungeon Scripts** | 1 example | No PvE endgame |
| ~~Dialogue Trees~~ | ✅ **10,799 entries extracted** | ✅ Wired to NPCs |

---

## Detailed Gap Analysis

### 1. Quest System (✅ Handlers Wired - Ready for Testing)

**What exists:**
- Database schemas: `Quest`, `QuestHistory` with full lifecycle
- Protocol packets: Accept, abandon, turn-in implemented
- ✅ **Handler wiring complete** - `QuestHandler` and `NpcHandler` implement `BezgelorProtocol.Handler` behaviour
- ✅ **Packet registration correct** - `client_accept_quest`, `client_abandon_quest`, `client_turn_in_quest`, `client_npc_interact`
- Progress tracking: JSON-based objective progress
- ✅ **5,194 quests extracted from client** (`quests.json`)
- ✅ **10,031 quest objectives** (`quest_objectives.json`)
- ✅ **5,415 quest rewards** (`quest_rewards.json`)
- ✅ **209 quest hubs** (`quest_hubs.json`)
- ✅ **53 quest categories** (`quest_categories.json`)
- ✅ **Quest giver/receiver mappings** (`creatures_part1-4.json` - `questIdGiven00-24`, `questIdReceive00-24` fields)
- ✅ **Store functions** - `get_quests_for_creature_giver/1`, `get_quests_for_creature_receiver/1`, `creature_quest_giver?/1`
- ✅ **PrerequisiteChecker** - Level, race, class, faction, quest chain validation
- ✅ **RewardHandler** - XP, gold, items, reputation grants

**What's needed:**
- ~~Wire quest data to existing quest system~~ → ✅ Complete
- ~~Map quest givers~~ → ✅ Available in creatures_full data
- End-to-end testing with actual client

**Impact:** ✅ Quest system is fully wired - data flows from NPC interaction through to rewards.

### 2. NPC/Vendor System (✅ COMPLETE)

**What exists:**
- 53,137 creature templates with full metadata (`creatures_part1-4.json`)
- Creature spawn system
- ✅ **881 vendor NPCs identified** (`npc_vendors.json`)
- ✅ **35,842 vendor item listings** (`vendor_inventories.json`)
- ✅ **569 creature affiliations** (vendor types, trainers, etc.)
- ✅ **10,799 gossip/dialogue entries** (`gossip_entries.json`)
- ✅ **1,978 gossip sets** (`gossip_sets.json`)
- ✅ **Creature → gossip mappings** (`gossipSetId` field in creatures_full)
- ✅ **Creature → faction mappings** (`factionId` field in creatures_full)

**Vendor types:**
- 162 General Goods, 87 Settler, 74 Quartermaster
- 53 Weapons, 51 Tradeskill Goods, 48 Armor
- 22 Cooking Trainers, 20 Ability Trainers, 15 Mount vendors
- Plus many specialized vendors (PvP, reputation, etc.)

**What's needed:**
- ~~Vendor inventory data~~ → ✅ Generated
- ~~Wire gossip system to NPCs~~ → `gossipSetId` mapping available

**Impact:** ✅ NPCs fully configured with inventories and dialogue mappings.

### 3. World Population (✅ COMPLETE for Open World)

**What exists:**
- 3,436 zone definitions with full metadata
- 41,056 creature spawns across all 7 open world continents
- 2,921 object spawns
- ✅ **5,015 harvest/resource node spawns** (extracted from NexusForever.WorldDatabase)
- Full import from NexusForever.WorldDatabase

**World coverage:**
| World ID | Continent | Zones | Creatures | Objects | Resources |
|----------|-----------|-------|-----------|---------|-----------|
| 51 | Alizar (Exile) | Algoroc, Celestion, Galeras, Thayd, Whitevale | 20,229 | 1,833 | 1,898 |
| 22 | Olyssia (Dominion) | Auroria, Deradune, Ellevar, Illium, Wilderrun | 996 | 30 | 1,619 |
| 1061 | Isigrol (Max-level) | Blighthaven, Malgrave, SouthernGrimvault, TheDefile, WesternGrimvault | 17,990 | 986 | 1,498 |
| 990 | EverstarGrove | Tutorial area | 1,107 | 49 | 0 |
| 426 | NorthernWilds | Tutorial area | 590 | 23 | 0 |
| 870 | CrimsonIsle | Dominion starter | 47 | 0 | 0 |
| 1387 | LevianBay | Shiphand area | 97 | 0 | 0 |

**Still missing:**
- Instance/dungeon creature spawns (separate data)

**Impact:** Open world is now populated. Players can explore, combat creatures, and gather resources.

### 4. Loot System (✅ 85% Complete)

**What exists:**
- ✅ Loot generation framework with level scaling
- ✅ Real item IDs from 71,918 items (Family 25 creature loot = 2,845 items)
- ✅ Creature race → loot category mappings (190+ races categorized)
- ✅ Loot tables by creature type (wildlife, humanoid, mechanical, elemental, insect, undead)
- ✅ Equipment drop system with tier-based chances (Tier 1-5)
- ✅ Group loot bonus wiring (0% solo → +23% raid)
- ✅ Gold amounts validated against quest reward economy

**Equipment drop chances by creature tier:**
| Tier | Type | Green | Blue | Purple | Orange |
|------|------|-------|------|--------|--------|
| 1 | Minion | - | - | - | - |
| 2 | Standard | 1% | 0.1% | - | - |
| 3 | Champion | 5% | 1% | 0.1% | - |
| 4 | Elite | 10% | 5% | 1% | - |
| 5 | Boss | - | 50% | 20% | 1% |

**What's missing:**
- Boss-specific unique drops
- Chest/container loot

**Impact:** ✅ Creatures now drop appropriate loot with real items and equipment.

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

### 6. Tradeskill Content (✅ 95% Complete)

**What exists:**
- 6 crafting + 3 gathering professions
- Schematics, talents, additives
- Coordinate-based crafting system
- Work order templates
- ✅ **5,015 gathering node spawns** across 3 continents
- ✅ **HarvestNodeManager** for zone spawning and respawns
- ✅ **Harvest node loot tables** - 83 unique nodes mapped to drops by profession/tier

**Harvest loot coverage:**
| Profession | Nodes | Drops |
|------------|-------|-------|
| Mining | 23 | Iron→Titanium→Platinum→Xenocite→Galactium + gems |
| Survivalist | 13 | Ancient→Augmented→Primal→Spirit→Iron hardwood + plants |
| Relic Hunter | 5 | Standard→Kinetic Omni-Plasm + Eldan components |
| Farming | 38 | Vegetables + seeds |
| Generic | 4 | Fallback for special nodes |

**What's missing:**
- Tutorial zone gathering nodes (EverstarGrove, NorthernWilds)
- Some instance/dungeon gathering nodes

**Impact:** ✅ Gathering professions fully functional with real loot drops.

---

## Gap Inventory (Ranked by Priority)

### Tier 1: Required for Basic Playability

| # | Gap | Impact | Effort | Data Source |
|---|-----|--------|--------|-------------|
| ~~1~~ | ~~Quest Content~~ | ~~Cannot progress~~ | ~~High~~ | ✅ **EXTRACTED** - 5,194 quests from client |
| ~~2~~ | ~~NPC/Vendor System~~ | ~~Cannot interact~~ | ~~Medium~~ | ✅ **EXTRACTED** - 881 vendors identified |
| ~~3~~ | ~~Zone Population~~ | ~~Empty world~~ | ~~Medium~~ | ✅ **COMPLETE** - 41,056 spawns imported |
| 1 | **Wire Quest System** | Data exists, needs integration | Medium | Map to existing handlers |
| 2 | **Vendor Inventories** | Vendors have no items | Medium | Generate or mine from Jabbithole |

### Tier 2: Required for Meaningful Gameplay

| # | Gap | Impact | Effort | Data Source |
|---|-----|--------|--------|-------------|
| ~~4~~ | ~~Loot Table Assignment~~ | ~~No rewards~~ | ~~Medium~~ | ✅ **COMPLETE** - Real items + equipment drops |
| ~~5~~ | ~~Gathering Node Spawns~~ | ~~Tradeskills broken~~ | ~~Medium~~ | ✅ **COMPLETE** - 5,015 nodes extracted |
| 6 | **Dungeon Encounters** | No PvE endgame | High | Manual scripting |

### Tier 3: Polish & Completeness

| # | Gap | Impact | Effort | Data Source |
|---|-----|--------|--------|-------------|
| ~~7~~ | ~~Dialogue System~~ | ~~NPCs silent~~ | ~~Medium~~ | ✅ **EXTRACTED** - 10,799 gossip entries |
| ~~8~~ | ~~Achievement System~~ | ~~No progress sense~~ | ~~Medium~~ | ✅ **EXTRACTED** - 4,943 achievements |
| ~~9~~ | ~~Path Mission Content~~ | ~~Paths empty~~ | ~~Medium~~ | ✅ **EXTRACTED** - 1,064 path missions |
| ~~7~~ | ~~**Wire Dialogue to NPCs**~~ | ✅ **Complete** | ~~Low~~ | ✅ Click + ambient gossip |
| 8 | **Wire Achievements** | Data exists, needs triggers | Medium | Map to game events |
| 9 | **Wire Path Missions** | Data exists, needs integration | Medium | Map to locations |
| 10 | **Additional Battlegrounds** | Limited PvP | Medium | Manual creation |

---

## Recommended Implementation Path

### Phase A: World Population ✅ COMPLETE

**A.1: Import NexusForever.WorldDatabase** ✅
```
Source: https://github.com/NexusForever/NexusForever.WorldDatabase
Content: 19 SQL files with creature spawn positions
Format: SQL → JSON → ETS loader
Result: 41,056 creatures + 2,921 objects across 7 worlds
Tool: tools/spawn_importer/nexusforever_converter.py
```

**A.2: Build NPC Layer** (TODO)
- Add `npc_type` enum to creature system
- Create `vendor_inventory` table
- Wire into existing spawn system

**A.3: Basic Loot Tables** ✅ COMPLETE
- ✅ Creature race → loot category mappings (190+ races)
- ✅ Real item IDs from client data (2,845 loot items)
- ✅ Equipment drops by creature tier (1-5)
- ✅ Group loot bonus wiring
- TODO: Boss-specific unique drops

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

**C.2: Gathering Nodes** ✅ COMPLETE
- ✅ 5,015 harvest nodes extracted from NexusForever.WorldDatabase
- ✅ HarvestNodeManager wired into zone spawning
- ✅ Respawn system implemented
- ✅ Loot tables for 83 unique node types (Mining, Survivalist, Relic Hunter, Farming)

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

| Task | Complexity | Status |
|------|------------|--------|
| WorldDatabase import | Medium | ✅ **COMPLETE** |
| Client data extraction | Medium | ✅ **COMPLETE** - 5,194 quests + all content |
| NPC/Vendor identification | Medium | ✅ **COMPLETE** - 881 vendors |
| Loot table wiring | Medium | ✅ **COMPLETE** - Real items + equipment drops |
| Wire quest data to system | Medium | ✅ **COMPLETE** - Handlers wired |
| Generate vendor inventories | Medium | ✅ **COMPLETE** - 35,842 items |
| Gathering nodes | Medium | ✅ **COMPLETE** - 5,015 nodes + 83 loot mappings |
| First dungeon complete | High | TODO |

**Minimum viable "playable" (level 1-20):** 1-2 weeks focused work (data extraction complete!)

---

## Data Sources

### NexusForever.WorldDatabase
- **URL:** https://github.com/NexusForever/NexusForever.WorldDatabase
- **Content:** Creature spawn positions by zone
- **Format:** SQL files organized by continent
- **Status:** ✅ **IMPORTED** - 41,056 creatures + 2,921 objects

### WildStar Client Data ✅ MAJOR EXTRACTION COMPLETE
- **Tool:** `tools/tbl_extractor/` + `Halon/halon.py`
- **Source:** `~/Downloads/wildstar_clientdata.archive` (12GB)
- **Total TBL files:** 384
- **Status:** ✅ **Major content extracted**

**Extracted content:**
| Category | Records | Files |
|----------|---------|-------|
| Creatures (Full) | 53,137 creatures, 173 fields each | `creatures_part1-4.json` (split for GitHub) |
| Quests | 5,194 quests, 10,031 objectives, 5,415 rewards | `quests.json`, `quest_objectives.json`, `quest_rewards.json` |
| NPCs | 881 vendors, 569 affiliations | `npc_vendors.json`, `creature_affiliations.json` |
| Achievements | 4,943 achievements, 273 categories | `achievements.json`, `achievement_categories.json` |
| Paths | 1,064 missions, 115 episodes | `path_missions.json`, `path_episodes.json` |
| Dialogue | 10,799 entries, 1,978 sets | `gossip_entries.json`, `gossip_sets.json` |
| Challenges | 643 challenges, 1,684 tiers | `challenges.json`, `challenge_tiers.json` |
| World | 33,396 locations, 62 bind points | `world_locations.json`, `bind_points.json` |
| Prerequisites | 32,131 prerequisites | `prerequisites.json` |

**Key fields in creatures_full (173 total):**
- `questIdGiven00-24` - Up to 25 quests this NPC can give
- `questIdReceive00-24` - Up to 25 quests this NPC can accept turn-ins for
- `gossipSetId` - Links to dialogue tree
- `factionId` - Faction alignment
- `minLevel`, `maxLevel` - Level range
- `bindPointId` - Associated bind point
- `taxiNodeId` - Flight path connection
- `tradeSkillIdTrainer` - Tradeskill training offered

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

Bezgelor represents an impressive technical achievement—a complete WildStar server architecture in Elixir with excellent code organization and comprehensive system implementations.

**Major breakthrough:** Client data extraction revealed massive content that was previously thought to be missing:
- **5,194 quests** with objectives and rewards
- **881 NPC vendors** with type classifications
- **4,943 achievements** with categories and checklists
- **1,064 path missions** for all four paths
- **10,799 dialogue entries** for NPC conversations
- **33,396 world locations** for quest directions
- **5,015 harvest nodes** for gathering professions (extracted from WorldDatabase)
- **83 harvest node loot mappings** by profession and tier (Mining, Survivalist, Relic Hunter, Farming)

The path to playability is now much clearer:
1. ~~Populate the world (WorldDatabase import)~~ ✅ **COMPLETE**
2. ~~Extract quest/NPC data from client~~ ✅ **COMPLETE**
3. Wire extracted data to existing systems
4. Generate/mine vendor inventories

With content extraction complete, a playable level 1-20 experience is achievable in **1-2 weeks** focused work. The remaining tasks are primarily integration work rather than content creation.

The architectural foundation is solid, and the content now exists. What remains is connecting the data to the systems—a much more tractable problem than the original content gap suggested.
