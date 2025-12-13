# Loot System Analysis

## Overview

This document details the investigation into extracting boss-specific loot data from WildStar client files, conducted December 2024.

## Objective

Determine if creature→item loot mappings exist in WildStar client data files to populate historically-accurate boss drop tables.

## Client Tables Examined

| Table | Records | Purpose | Loot Data? |
|-------|---------|---------|------------|
| Creature2.tbl | 53,137 | Creature definitions, stats, display | No loot fields |
| LootSpell.tbl | 533 | Loot pickup spell visuals | creature2Id for visuals only |
| LootPinataInfo.tbl | 163 | Loot container definitions | item2FamilyId for random loot pools |
| VirtualItem.tbl | 1,046 | Virtual item definitions | No creature mappings |
| Quest2Reward.tbl | 5,415 | Quest completion rewards | Quest→item, not creature→item |
| MatchingRandomReward.tbl | 15 | Dungeon/raid completion rewards | Instance completion only |
| Creature2Tier.tbl | 27 | Creature tier stat multipliers | No loot data |
| Creature2Difficulty.tbl | 24 | Difficulty stat multipliers | No loot data |
| RewardProperty.tbl | 34 | Reward type definitions | Metadata only |
| RewardRotationItem.tbl | 6 | Daily reward rotation | Login rewards only |
| CombatReward.tbl | 19 | Combat reward types | XP/reputation types |

## Key Findings

### Creature2.tbl Structure

The main creature table contains 53,137 records with fields including:
- `creature2TierId` - References stat multipliers
- `creature2DifficultyId` - Difficulty classification
- `item2IdMTXKey00/01` - MTX key items (cosmetic)
- `itemIdDisplayItemRight` - Display weapon

**No loot table ID or drop list reference exists.**

### LootPinataInfo.tbl

Defines loot containers with:
- `creature2IdChest` - Visual creature for loot bag
- `item2FamilyId` - Item family for random generation
- `item2TypeId`, `item2CategoryId` - Filtering parameters

This system generates random loot based on item family/type/category, not specific boss drops.

### NexusForever Reference

The NexusForever C# emulator (which this project is ported from) confirms this finding:

```csharp
// Source/NexusForever.Game/Entity/UnitEntity.cs:447-448
protected virtual void RewardKiller(IPlayer player)
{
    // ...quest objective updates...

    // TODO: Reward XP
    // TODO: Reward Loot
    // TODO: Handle Achievements
}
```

NexusForever also lacks boss loot implementation, indicating the data was never found in client files.

## Conclusion

**Boss→item loot mappings were server-side data in WildStar.**

The client contains:
- Item definitions (stats, visuals, requirements)
- Random loot generation parameters (families, types, categories)
- Quest/instance completion rewards

The client does NOT contain:
- Specific boss drop tables
- Creature→item mappings
- Drop rates for specific encounters

## Implementation Approach

Since historical boss loot data is unavailable, loot tables were generated using:

### Item Selection Criteria

1. **Quality filtering** from Item2.tbl:
   - Genetic Archives (GA): `quality_id = 4` (Epic)
   - Datascape (DS): `quality_id = 5` (Legendary)

2. **Level filtering**:
   - GA bosses: Item level 100-116
   - DS bosses: Item level 120+

3. **Slot distribution**: Each boss drops items appropriate to their encounter (weapons, armor, accessories)

### Loot Table Structure

```json
{
  "id": 300106,
  "name": "Raid Boss - Dreadphage Ohmna",
  "entries": [
    {"item_id": 0, "chance": 100, "min": 1500, "max": 2500, "type": "gold"},
    {"item_id": 16487, "chance": 100, "min": 1, "max": 1, "type": "item"},
    {"item_id": 16488, "chance": 50, "min": 1, "max": 1, "type": "item"}
  ]
}
```

### ID Scheme

| Range | Content |
|-------|---------|
| 1-19 | Generic loot tables |
| 100101-100405 | Dungeon boss loot (4 dungeons, 4 bosses each) |
| 300101-300106 | Genetic Archives boss loot (6 bosses) |
| 300201-300209 | Datascape boss loot (9 bosses) |

## Files Modified

- `apps/bezgelor_data/priv/data/loot_tables.json` - Added 15 raid boss loot tables
- `apps/bezgelor_data/priv/data/instance_bosses.json` - Already had loot_table_id references

## Future Improvements

If historical data surfaces from:
- Archived guild databases
- WildStar community wikis
- Data mining efforts

The loot tables can be updated to reflect accurate boss→item mappings. The current structure supports this without code changes.

## References

- Extracted client data: `/tmp/loot_extract/`
- Item database: `apps/bezgelor_data/priv/data/items.json`
- NexusForever source: `/Users/jrimmer/work/nexusforever/`
