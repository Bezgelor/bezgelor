# NexusForever WorldDatabase Data Inventory

This document describes the data extracted from the NexusForever WorldDatabase SQL dumps and how it's used in Bezgelor.

## Overview

The NexusForever project provides a MySQL database dump containing hand-curated spawn data for the WildStar game world. Bezgelor converts this SQL data to JSON format for loading into ETS at runtime.

**Source Repository:** https://github.com/NexusForever/NexusForever.WorldDatabase

**Converter Tool:** `tools/spawn_importer/nexusforever_converter.py`

**Output File:** `apps/bezgelor_data/priv/data/creature_spawns.json`

## SQL Tables Parsed

### Core Entity Tables

| Table | Description | Fields Used |
|-------|-------------|-------------|
| `entity` | Main spawn definitions | id, type, creature, world, area, x/y/z, rx/ry/rz, displayInfo, outfitInfo, faction1/2, questChecklistIdx, activePropId |
| `entity_spline` | Patrol path assignments | id, splineId, splineMode, speed |
| `entity_stats` | Stat overrides | id, stat, value |

### Extended Entity Tables

| Table | Description | Fields Used | Current Usage |
|-------|-------------|-------------|---------------|
| `entity_event` | Phased content triggers | id, eventId, phase | Parsed, not yet wired |
| `entity_property` | Special property overrides | id, propertyId, value | Parsed, not yet wired |
| `entity_script` | Boss AI script bindings | id, scriptName | Parsed, not yet wired |

### Instance/Map Tables

| Table | Description | Fields Used | Current Usage |
|-------|-------------|-------------|---------------|
| `map_entrance` | Instance spawn points | mapId, team, worldLocationId | Parsed, not yet wired |

### Vendor Tables

| Table | Description | Fields Used | Current Usage |
|-------|-------------|-------------|---------------|
| `entity_vendor` | Vendor price multipliers | id, buyPriceMultiplier, sellPriceMultiplier | Parsed, not yet wired |
| `entity_vendor_category` | Vendor item categories | id, index, localizedTextId | Parsed, not yet wired |
| `entity_vendor_item` | Items sold by vendors | id, index, categoryIndex, itemId | Parsed, not yet wired |

## Entity Types

NexusForever uses the following entity type constants (from `EntityType` enum):

| Type | Value | Description | Bezgelor Usage |
|------|-------|-------------|----------------|
| NPC | 0 | Non-player characters (vendors, quest givers) | creature_spawns |
| RESOURCE | 5 | Gathering nodes (mining, relic hunting) | resource_spawns |
| OBJECT | 8 | Interactive objects | object_spawns |
| CREATURE | 10 | Standard creatures/mobs | creature_spawns |
| BINDPOINT | 19 | Resurrection/graveyard points | bindpoint_spawns |
| STRUCTURE | 32 | Buildings, collision objects | Not currently extracted |

## Output JSON Structure

```json
{
  "source": "NexusForever.WorldDatabase",
  "zone_spawns": [
    {
      "world_id": 1387,
      "zone_name": "LevianBay",
      "creature_spawns": [
        {
          "id": 12345,
          "creature_id": 6789,
          "position": [100.0, 200.0, 50.0],
          "rotation": [0.0, 0.0, 1.57],
          "area_id": 1411,
          "display_info": 0,
          "outfit_info": 0,
          "faction1": 171,
          "faction2": 171,
          "respawn_time_ms": 300000,
          "patrol_path_id": 42,
          "patrol_speed": 1.0,
          "patrol_mode": 0,
          "stat_overrides": [
            {"stat_id": 1, "value": 1000.0}
          ],
          "events": [
            {"event_id": 100, "phase": 1}
          ],
          "properties": [
            {"property_id": 5, "value": 2.0}
          ],
          "script_name": "BossAI_Stormtalon",
          "vendor": {
            "buy_price_multiplier": 1.0,
            "sell_price_multiplier": 1.0,
            "categories": [
              {"index": 0, "localized_text_id": 12345}
            ],
            "items": [
              {"index": 0, "category_index": 0, "item_id": 67890}
            ]
          }
        }
      ],
      "resource_spawns": [...],
      "object_spawns": [...],
      "bindpoint_spawns": [...],
      "map_entrances": [
        {"team": 0, "world_location_id": 24958}
      ],
      "vendors": []
    }
  ]
}
```

## Current Statistics

As of December 2025:

| Data Type | Count | Notes |
|-----------|-------|-------|
| Zones | 10 | Unique world_ids |
| Creature Spawns | 65,849 | NPCs + Creatures |
| Resource Spawns | 5,015 | Gathering nodes |
| Object Spawns | 4,383 | Interactive objects |
| Bindpoint Spawns | 44 | Resurrection points |
| Map Entrances | 5 | Instance spawn points |

## SQL Variable Handling

The NexusForever SQL files use variables to reduce duplication:

| Variable | Description | Example |
|----------|-------------|---------|
| `@WORLD` | Current world ID | `SET @WORLD = 1387;` |
| `@GUID` | Base entity ID for file | `SET @GUID = 100000;` |
| `@GUID+N` | Entity ID offset | `(@GUID+1, ...)` |
| `@EVENTID` | Event ID for phased content | `SET @EVENTID = 42;` |

The converter properly resolves these variables when parsing.

## Usage in Bezgelor

### Loading Spawn Data

```elixir
# In BezgelorData.Store
def get_creature_spawns(world_id) do
  data = load_json("creature_spawns.json")

  data["zone_spawns"]
  |> Enum.find(& &1["world_id"] == world_id)
  |> Map.get("creature_spawns", [])
end
```

### World Instance Spawn Loading

```elixir
# In BezgelorWorld.World.Instance
def handle_continue(:load_spawns, state) do
  spawns = BezgelorData.Store.get_creature_spawns(state.world_id)

  # Create entities from spawn definitions
  entities = Enum.map(spawns, &spawn_to_entity/1)

  {:noreply, %{state | entities: entities}}
end
```

## Converter Usage

```bash
# Download latest SQL files from GitHub
python3 tools/spawn_importer/nexusforever_converter.py download

# Convert single file
python3 tools/spawn_importer/nexusforever_converter.py convert \
  /path/to/LevianBay.sql /path/to/output.json

# Merge all SQL files into single JSON
python3 tools/spawn_importer/nexusforever_converter.py merge \
  /Users/jrimmer/work/NexusForever.WorldDatabase \
  apps/bezgelor_data/priv/data/creature_spawns.json
```

After regenerating, clear the ETF cache:

```bash
rm -f apps/bezgelor_data/priv/data/cache/*.etf
```

## Future Work

### Not Yet Wired

1. **entity_event** - Phased content (show/hide entities based on quest progress)
2. **entity_property** - Custom property overrides (damage multipliers, etc.)
3. **entity_script** - Boss AI scripts (need script execution engine)
4. **map_entrance** - Instance spawn points (need instance system)
5. **entity_vendor** - Vendor data (need vendor UI/transaction system)

### Tables Not Yet Parsed

These tables exist in NexusForever but aren't yet parsed:

| Table | Purpose | Priority |
|-------|---------|----------|
| `entity_spline_point` | Individual waypoints for patrol paths | High - needed for patrol movement |
| `npc_vendor` | Alternative vendor data format | Low - duplicate of entity_vendor |
| `store_category`, `store_offer` | Cash shop data | Medium - for storefront |

## Troubleshooting

### Missing Entities

If entities appear missing:

1. Check column count in SQL - converter requires >= 15 columns
2. Check for `@GUID+N` variables - must use `_parse_int_or_var()`
3. Verify world_id matches expected zone

### Cache Issues

If changes don't appear after regeneration:

```bash
# Clear ETF cache
rm -f apps/bezgelor_data/priv/data/cache/*.etf

# Restart application
mix run --no-halt
```

## Related Documentation

- [Architecture Overview](./architecture.md)
- [Per-Zone Creature Manager](./plans/2025-12-23-per-zone-creature-manager.md)
- [Content Status](./content.md)
