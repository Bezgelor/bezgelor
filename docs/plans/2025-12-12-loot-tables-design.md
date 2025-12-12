# Loot Tables System Design

**Date:** 2025-12-12
**Status:** Implemented (Revised)
**Last Updated:** 2025-12-12

## Problem Statement

The existing loot system used hardcoded test tables with simple chance-based drops. This didn't scale for a real game and lacked:
- Data-driven configuration
- Level-based scaling
- Group/raid bonuses
- Creature-specific loot mapping

## Research Findings

### WildStar Client Data

Extracted from the WildStar archive:
- `LootPinataInfo.tbl` (163 records) - Defines loot container visuals by item type/category
- `LootSpell.tbl` (533 records) - Defines spell effects when looting

**Key insight:** WildStar's actual loot tables were server-side only. The client data only contains visual/UI information. NexusForever hasn't implemented creature loot yet (it's in their MVP milestone).

### Decision

Design our own data-driven loot system that can be populated with custom content or eventually real WildStar data if discovered.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ creature_id     │────▶│ creature_loot.   │────▶│ loot_tables.    │
│ creature_level  │     │ json (rules)     │     │ json (tables)   │
│ (from entity)   │     └──────────────────┘     └─────────────────┘
└─────────────────┘                                       │
                                                          ▼
                                                 ┌─────────────────┐
                                                 │ BezgelorWorld.  │
                                                 │ Loot            │
                                                 └─────────────────┘
```

**Note:** Module lives in `bezgelor_world` (not `bezgelor_core`) to maintain correct dependency direction: world → data → core.

### Resolution Flow

1. `roll_creature_loot(creature_id, creature_level, killer_level, opts)` is called on creature death
2. `Store.resolve_creature_loot(creature_id)` checks for:
   - Direct override (specific creature has custom loot)
   - Rule-based resolution using creature's `race_id`, `tier_id`, `difficulty_id`
3. Resolution returns `{:ok, %{loot_table_id, gold_multiplier, drop_bonus, extra_table}}`
4. Level scaling adjusts gold and drop rates based on killer vs creature level
5. Group bonus is calculated from `group_size` option
6. `roll_table(loot_table_id)` rolls against entries with combined modifiers

## Data Structures

### loot_tables.json

23 loot tables covering all creature categories:

```json
{
  "loot_tables": [
    {
      "id": 1,
      "name": "Basic Wildlife - Small",
      "entries": [
        {"item_id": 0, "chance": 100, "min": 1, "max": 3, "type": "gold"},
        {"item_id": 27645, "chance": 25, "min": 1, "max": 1, "type": "item", "name": "Rawhide Scraps"}
      ]
    }
  ]
}
```

Entry fields:
- `item_id` - Item template ID (0 = gold/currency)
- `chance` - Drop chance percentage (1-100)
- `min`/`max` - Quantity range
- `type` - "gold" or "item"
- `name` - Human-readable name (documentation only)

### creature_loot.json

Comprehensive rule-based mapping based on analysis of 53,137 creatures across 190 races:

```json
{
  "creature_loot_rules": {
    "race_mappings": {
      "37": {"category": "humanoid", "base_table": 10, "note": "Warders, humanoid NPCs"},
      "47": {"category": "wildlife", "base_table": 1, "note": "Dagun - reptile wildlife"},
      "61": {"category": "plant", "base_table": 60, "note": "Hemovorous, Stemdragon"},
      "default": {"category": "wildlife", "base_table": 1}
    },
    "tier_modifiers": {
      "1": {"table_offset": 0, "gold_multiplier": 1.0, "drop_bonus": 0},
      "5": {"table_offset": 0, "gold_multiplier": 5.0, "drop_bonus": 20, "extra_table": 100},
      "11": {"table_offset": 0, "gold_multiplier": 12.0, "drop_bonus": 32, "extra_table": 200, "note": "Boss tier"},
      "18": {"table_offset": 0, "gold_multiplier": 50.0, "drop_bonus": 50, "extra_table": 200, "note": "World boss tier"}
    },
    "difficulty_modifiers": {
      "4": {"gold_multiplier": 1.0, "drop_bonus": 0, "note": "Normal"},
      "24": {"gold_multiplier": 8.0, "drop_bonus": 50, "note": "Extreme"}
    }
  }
}
```

## Loot Tables Created

| ID | Name | Use Case |
|----|------|----------|
| 1-3 | Wildlife (Small/Medium/Large) | Beasts, animals |
| 10-11 | Humanoid (Basic/Armed) | Human-like enemies |
| 20-23 | Elementals (Fire/Earth/Air/Water) | Elemental creatures |
| 30-31 | Mechanical (Basic/Advanced) | Robots, machines |
| 40-41 | Strain (Basic/Elite) | Corrupted creatures |
| 50-51 | Insect (Basic/Large) | Bugs, spiders |
| 60-61 | Plant (Basic/Large) | Plant creatures |
| 70-71 | Avian (Basic/Large) | Flying creatures |
| 80-81 | Aquatic (Basic/Large) | Fish, water creatures |
| 100 | Elite Generic | Bonus table for elite mobs |
| 200 | Boss Dungeon | Dungeon boss base loot |
| 999 | Empty | NPCs, non-combat creatures |

## Race Mappings

All 190 creature races are now mapped. Key categorizations:

| Category | Example Races | Table IDs |
|----------|--------------|-----------|
| Humanoid | 37 (Warders), 69-72, 76-78, 95, 135-172 | 10-11 |
| Wildlife | 47, 49, 96, 99, 115, 131, 139, 154, 163 | 1-3 |
| Mechanical | 80, 81, 205-207, 267, 276 | 30-31 |
| Elemental | 87 (fire), 119, 121, 164 (earth) | 20-23 |
| Insect | 105, 149, 156, 169 | 50-51 |
| Plant | 61 | 60-61 |
| Avian | 84, 113, 124, 125 | 70-71 |
| Aquatic | 100 | 80-81 |
| Strain | 184 | 40-41 |
| No Loot | 0, 88, 204, 268, 270 | 999 |

## Modifiers

### Level Scaling

| Level Difference | Gold Scale | Drop Bonus |
|-----------------|------------|------------|
| Creature 10+ below | 0.25x | -20% |
| Creature 6-10 below | 0.50x | -10% |
| Creature 3-5 below | 0.75x | -5% |
| Normal range (±2) | 1.0x | 0% |
| Creature 3-5 above | 1.25x | +5% |
| Creature 6-10 above | 1.50x | +10% |
| Creature 10+ above | 2.0x | +15% |

### Tier Modifiers (1-18)

Tiers 1-4 are standard mobs with increasing rewards.
Tiers 5-10 add elite bonus table (100).
Tiers 11-18 add boss bonus table (200) with up to 50x gold multiplier.

### Difficulty Modifiers (0-24)

From trivial (0) with 0.25x gold to extreme (24) with 8x gold.

### Group Bonus

| Group Size | Drop Bonus |
|-----------|------------|
| Solo | 0% |
| 2-5 players | +2% per player after first |
| 6-20 players | +8% base + 1% per player |
| 20+ players | +23% (cap) |

## API

```elixir
# Roll loot for a creature kill (4 parameters)
BezgelorWorld.Loot.roll_creature_loot(creature_id, creature_level, killer_level, opts \\ [])

# Options:
# - group_size: integer (for group bonus)
# - no_gold: boolean (skip gold drops)
# - bonus_chance: number (additional drop chance)

# Roll from specific table with modifiers
Loot.roll_table(table_id, gold_multiplier: 1.5, drop_bonus: 10)

# Roll from entry list (for custom scenarios)
Loot.roll_entries(entries, opts)

# Utility functions
Loot.gold_from_drops(drops)
Loot.items_from_drops(drops)
Loot.has_gold?(drops)
Loot.has_items?(drops)
Loot.calculate_group_bonus(group_size)
```

## Integration Points

### Creature Death (creature_manager.ex, zone_manager.ex)

```elixir
# On creature death
creature_level = template.level
killer_level = get_killer_level(killer_guid, template.level, state)
creature_id = entity.creature_id
loot_drops = Loot.roll_creature_loot(creature_id, creature_level, killer_level)
```

### Future Integration

- Quest rewards can use `roll_entries/2` directly
- Event loot already uses similar structure in `event_loot_tables.json`
- Gathering nodes could use `roll_table/2`

## Testing

18 tests in `BezgelorWorld.LootTest` covering loot rules.
Additional tests needed for data-driven loot rolling with Store integration.

## Known Limitations

### Item IDs Are Placeholders

All item IDs in loot tables (27645, 27700, 28000, etc.) are invented placeholders. Real item IDs would need to be extracted from WildStar item data.

### Gold Amounts Are Estimates

Gold drop amounts are reasonable guesses based on tier/difficulty. Actual WildStar economy data was server-side only.

### Many Races Unmapped in Detail

While all 190 races have a category mapping, many "Unknown" races are defaulted to wildlife. A more thorough investigation of creature names would improve categorization.

### No Equipment Drops

The system only supports generic item drops, not equipment with random stats or sockets.

### Group Size Not Yet Wired

The `group_size` option exists but isn't passed from death handlers. Players don't have group membership tracked yet.

## Revision History

| Date | Changes |
|------|---------|
| 2025-12-12 | Initial implementation |
| 2025-12-12 | Moved module to bezgelor_world, fixed API to 4 params, comprehensive race mappings (190), extended tier/difficulty modifiers, added plant/avian/aquatic categories, removed legacy table fallback |

## Future Enhancements

1. **Equipment drops** - Roll random stats on equipment
2. **Rarity system** - Common/Uncommon/Rare/Epic/Legendary
3. **Personal loot** - Each player gets independent rolls
4. **Bad luck protection** - Increase chance after failed rolls
5. **Zone-specific bonuses** - Certain zones have better loot
6. **Time-limited events** - Holiday loot tables
7. **Group size wiring** - Pass actual party size to loot system
8. **Data validation** - Validate loot table and rule data on load
