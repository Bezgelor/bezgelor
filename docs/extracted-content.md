# Bezgelor Content Overview

This document provides an overview of all game content data available in Bezgelor, extracted from the WildStar client and imported from community databases.

## Data Summary

| Category | Records | Source |
|----------|---------|--------|
| **Quests** | 5,194 | Client extraction |
| **Quest Objectives** | 10,031 | Client extraction |
| **Quest Rewards** | 5,415 | Client extraction |
| **Creatures** | 53,137 | Client extraction |
| **Creature Spawns** | 65,849 | NexusForever.WorldDatabase |
| **Items** | 71,918 | Client extraction |
| **NPC Vendors** | 881 | Client extraction |
| **Vendor Inventory Items** | 35,842 | Generated |
| **Achievements** | 4,943 | Client extraction |
| **Path Missions** | 1,064 | Client extraction |
| **Gossip/Dialogue** | 10,799 | Client extraction |
| **Challenges** | 643 | Client extraction |
| **World Locations** | 33,396 | Client extraction |
| **Zones** | 3,436 | Client extraction |
| **Texts (i18n)** | Full | Client extraction |

**Total: 116,000+ records across 25 ETS tables**

---

## Quest Data

### Quests (5,194 records)
Quest definitions including type, zone, prerequisites, and text references.

```elixir
BezgelorData.get_quest(1177)
# => {:ok, %{id: 1177, type: 6, worldZoneId: 1480, ...}}

BezgelorData.quests_for_zone(1480)
# => [%{id: 1177, ...}, %{id: 1178, ...}, ...]
```

### Quest Objectives (10,031 records)
Individual objectives for each quest with type and completion criteria.

### Quest Rewards (5,415 records)
Rewards granted upon quest completion (items, XP, currency, reputation).

```elixir
BezgelorData.quest_rewards(1177)
# => [%{id: 158, quest2Id: 1177, objectId: 177, ...}]
```

### Quest Categories (53 records)
Organizational categories for quest UI grouping.

### Quest Hubs (209 records)
Geographic quest hub locations for quest tracking.

---

## NPC & Vendor Data

### NPC Vendors (881 records)
NPCs identified as vendors with type classification.

**Vendor Types:**
| Type | Count |
|------|-------|
| General Goods | 162 |
| Settler | 87 |
| Quartermaster | 74 |
| Weapons | 53 |
| Tradeskill Goods | 51 |
| Armor | 48 |
| Cooking Trainer | 22 |
| Ability Trainer | 20 |
| Mounts | 15 |
| *80+ other types* | Various |

```elixir
BezgelorData.is_vendor?(45014)
# => true

BezgelorData.vendors_by_type("weapons")
# => [%{id: 1, name: "Arms Dealer Dregaru", ...}, ...]
```

### Vendor Inventories (35,842 item entries)
Generated inventories mapping vendor types to appropriate items.

```elixir
BezgelorData.get_vendor_items(45014)
# => [%{item_id: 18995, quantity: -1, price_multiplier: 1.0}, ...]
```

### Creature Affiliations (569 records)
NPC type classifications (vendor, trainer, quest giver, etc.).

---

## Dialogue Data

### Gossip Entries (10,799 records)
Individual dialogue lines for NPC conversations.

```elixir
BezgelorData.get_gossip_text(entry_id)
# => "Welcome to Thayd, traveler!"
```

### Gossip Sets (1,978 records)
Groupings of gossip entries for conversation flows.

```elixir
BezgelorData.gossip_entries_for_set(set_id)
# => [%{id: 1, localizedTextId: 12345, ...}, ...]
```

---

## Achievement Data

### Achievements (4,943 records)
Achievement definitions with categories and zone associations.

```elixir
BezgelorData.get_achievement(342)
# => {:ok, %{id: 342, achievementCategoryId: 195, ...}}

BezgelorData.achievements_for_zone(483)
# => [%{id: 342, ...}, %{id: 343, ...}, ...]
```

### Achievement Categories (273 records)
Hierarchical categories for achievement organization.

### Achievement Checklists (6,568 records)
Sub-objectives within achievements (multi-part achievements).

---

## Path Mission Data

### Path Missions (1,064 records)
Missions for all four player paths.

| Path | Type ID | Missions |
|------|---------|----------|
| Soldier | 0 | ~266 |
| Settler | 1 | ~266 |
| Scientist | 2 | ~266 |
| Explorer | 3 | ~266 |

```elixir
BezgelorData.path_missions_by_type(0)  # Soldier missions
# => [%{id: 33, pathTypeEnum: 0, ...}, ...]
```

### Path Episodes (115 records)
Episode groupings for path mission progression.

### Path Rewards (302 records)
Rewards for path mission completion.

---

## Challenge Data

### Challenges (643 records)
Zone-based timed challenges.

```elixir
BezgelorData.challenges_for_zone(zone_id)
# => [%{id: 1, worldZoneId: 483, ...}, ...]
```

### Challenge Tiers (1,684 records)
Bronze/Silver/Gold tier requirements and rewards.

---

## World Location Data

### World Locations (33,396 records)
3D positions for quest markers, NPCs, and points of interest.

```elixir
BezgelorData.get_world_location(74)
# => {:ok, %{id: 74, worldId: 46, position0: 45.0, position1: 12.19, position2: 50.0}}

BezgelorData.world_locations_for_zone(zone_id)
# => [%{id: 74, ...}, %{id: 75, ...}, ...]
```

### Bind Points (62 records)
Respawn/teleport locations.

### Prerequisites (32,131 records)
Unlock conditions for content (level, quest completion, faction, etc.).

---

## World Population

### Creature Spawns (65,849 records)
Imported from NexusForever.WorldDatabase.

| World ID | Continent | Creatures | Resources | Objects |
|----------|-----------|-----------|-----------|---------|
| 51 | Alizar (Exile) | 20,229 | 1,833 | 1,833 |
| 22 | Olyssia (Dominion) | 996 | 30 | 30 |
| 1061 | Isigrol (Max-level) | 17,990 | 986 | 986 |
| 990 | EverstarGrove | 1,107 | 49 | 49 |
| 426 | NorthernWilds | 673 | 82 | 23 |
| 870 | CrimsonIsle | 47 | 0 | 0 |
| 1387 | LevianBay | 1,367 | 121 | 0 |
| + 3 others | Various | ~23,440 | ~1,914 | ~1,462 |

### Object Spawns (2,921 records)
Interactive objects, chests, and world objects.

---

## Secondary Indexes

Fast O(1) lookups via ETS secondary indexes:

| Index | Purpose |
|-------|---------|
| `quests_by_zone` | Find all quests in a zone |
| `quest_rewards_by_quest` | Find rewards for a quest |
| `vendors_by_creature` | Check if creature is a vendor |
| `vendors_by_type` | Find vendors by type |
| `gossip_entries_by_set` | Get dialogue for a gossip set |
| `achievements_by_category` | Achievements in a category |
| `achievements_by_zone` | Achievements for a zone |
| `path_missions_by_episode` | Missions in an episode |
| `path_missions_by_type` | Missions by path type |
| `challenges_by_zone` | Challenges in a zone |
| `world_locations_by_world` | Locations in a world |
| `world_locations_by_zone` | Locations in a zone |

---

## Data Files

All data stored in `apps/bezgelor_data/priv/data/`:

### Client Extracted (JSON)
- `quests.json` - Quest definitions
- `quest_objectives.json` - Quest objectives
- `quest_rewards.json` - Quest rewards
- `quest_categories.json` - Quest categories
- `quest_hubs.json` - Quest hub locations
- `npc_vendors.json` - Vendor NPCs
- `creature_affiliations.json` - NPC type classifications
- `gossip_entries.json` - Dialogue lines
- `gossip_sets.json` - Dialogue groupings
- `achievements.json` - Achievement definitions
- `achievement_categories.json` - Achievement categories
- `achievement_checklists.json` - Achievement sub-objectives
- `path_missions.json` - Path missions
- `path_episodes.json` - Path episodes
- `path_rewards.json` - Path rewards
- `challenges.json` - Challenge definitions
- `challenge_tiers.json` - Challenge tiers
- `world_locations.json` - 3D positions
- `bind_points.json` - Respawn locations
- `prerequisites.json` - Unlock conditions

### Generated
- `vendor_inventories.json` - Vendor item mappings (35,842 items)

### Imported (NexusForever.WorldDatabase)
- `creature_spawns.json` - World spawn positions

---

## API Module

All data accessible via `BezgelorData` module:

```elixir
# Statistics
BezgelorData.stats()
# => %{quests: 5194, achievements: 4943, ...}

# Quest API
BezgelorData.get_quest(id)
BezgelorData.quests_for_zone(zone_id)
BezgelorData.quest_rewards(quest_id)

# Vendor API
BezgelorData.is_vendor?(creature_id)
BezgelorData.get_vendor_items(creature_id)
BezgelorData.vendors_by_type("weapons")

# Achievement API
BezgelorData.get_achievement(id)
BezgelorData.achievements_for_zone(zone_id)

# Path API
BezgelorData.path_missions_by_type(0)  # Soldier

# Challenge API
BezgelorData.challenges_for_zone(zone_id)

# World Location API
BezgelorData.get_world_location(id)
BezgelorData.world_locations_for_zone(zone_id)
```

---

## Performance

- All data loaded into ETS at startup (~3 seconds)
- Read operations are O(1) via ETS lookups
- Secondary indexes provide O(1) foreign key lookups
- Memory footprint: ~200MB for all data
- Thread-safe concurrent reads via ETS `read_concurrency: true`

---

## Data Sources

1. **WildStar Client Archive** (12GB)
   - Extracted using `Halon/halon.py` and `tools/tbl_extractor/`
   - 384 TBL files processed

2. **NexusForever.WorldDatabase**
   - https://github.com/NexusForever/NexusForever.WorldDatabase
   - SQL spawn data converted to JSON

3. **Generated Content**
   - Vendor inventories via `tools/vendor_inventory_generator.py`

---

## Related Documentation

- [Data Wiring Complete](docs/2025-12-12-data-wiring-complete.md) - Implementation details
- [Playability Gap Analysis](docs/playability_gap_analysis.md) - Remaining work
- [Project Status](STATUS.md) - Overall project status
