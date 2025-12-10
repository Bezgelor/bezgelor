#!/usr/bin/env python3
"""
Extract WildStar game data and prepare it for Bezgelor.

This script extracts specific .tbl files needed by the Bezgelor server
and converts them to the JSON format expected by BezgelorData.

Usage:
    python extract_game_data.py <tbl_directory> [output_directory]

If output_directory is not specified, outputs to ../../apps/bezgelor_data/priv/data/
"""

import argparse
import json
import os
import sys
from pathlib import Path

from tbl_extractor import TblExtractor


# Mapping of .tbl files to output filenames and transformations
TABLE_CONFIG = {
    'Creature2.tbl': {
        'output': 'creatures.json',
        'key': 'creatures',
        'transform': lambda records: [transform_creature(r) for r in records if should_include_creature(r)]
    },
    'WorldZone.tbl': {
        'output': 'zones.json',
        'key': 'zones',
        'transform': lambda records: [transform_zone(r) for r in records if should_include_zone(r)]
    },
    'Spell4.tbl': {
        'output': 'spells.json',
        'key': 'spells',
        'transform': lambda records: [transform_spell(r) for r in records]
    },
    'Item2.tbl': {
        'output': 'items.json',
        'key': 'items',
        'transform': lambda records: [transform_item(r) for r in records if should_include_item(r)]
    },
}


def should_include_creature(record: dict) -> bool:
    """Filter creatures to include."""
    # Include creatures with valid IDs
    return record.get('ID', 0) > 0


def transform_creature(record: dict) -> dict:
    """Transform creature record to Bezgelor format.

    Actual fields from Creature2.tbl:
    - ID, CreationTypeEnum, description, localizedTextIdName
    - creature2AoiSizeEnum, unitRaceId, creature2DifficultyId
    - creature2ArcheTypeId, creature2TierId, creature2ModelInfoId
    - creature2DisplayGroupId, creature2OutfitGroupId
    - prerequisiteIdVisibility, modelScale, spell4IdActivate00-03
    """
    return {
        'id': record.get('ID', 0),
        'name_text_id': record.get('localizedTextIdName', 0),
        'description': record.get('description', ''),
        'race_id': record.get('unitRaceId', 0),
        'difficulty_id': record.get('creature2DifficultyId', 0),
        'archetype_id': record.get('creature2ArcheTypeId', 0),
        'tier_id': record.get('creature2TierId', 0),
        'model_info_id': record.get('creature2ModelInfoId', 0),
        'display_group_id': record.get('creature2DisplayGroupId', 0),
        'outfit_group_id': record.get('creature2OutfitGroupId', 0),
        'model_scale': record.get('modelScale', 1.0),
        'creation_type': record.get('CreationTypeEnum', 0),
        'aoi_size': record.get('creature2AoiSizeEnum', 0),
        'spells': [
            record.get('spell4IdActivate00', 0),
            record.get('spell4IdActivate01', 0),
            record.get('spell4IdActivate02', 0),
            record.get('spell4IdActivate03', 0),
        ],
    }


def should_include_zone(record: dict) -> bool:
    """Filter zones to include."""
    return record.get('ID', 0) > 0


def transform_zone(record: dict) -> dict:
    """Transform zone record to Bezgelor format.

    Actual fields from WorldZone.tbl:
    - ID, localizedTextIdName, parentZoneId, allowAccess
    - color, soundZoneKitId, worldLocation2IdExit, flags
    - zonePvpRulesEnum, rewardRotationContentId
    """
    return {
        'id': record.get('ID', 0),
        'name_text_id': record.get('localizedTextIdName', 0),
        'parent_zone_id': record.get('parentZoneId', 0) or None,
        'allow_access': record.get('allowAccess', True),
        'color': record.get('color', 0),
        'sound_zone_kit_id': record.get('soundZoneKitId', 0),
        'exit_location_id': record.get('worldLocation2IdExit', 0),
        'flags': record.get('flags', 0),
        'pvp_rules': record.get('zonePvpRulesEnum', 0),
        'reward_rotation_id': record.get('rewardRotationContentId', 0),
    }


def transform_spell(record: dict) -> dict:
    """Transform spell record to Bezgelor format.

    Actual fields from Spell4.tbl:
    - ID, description, spell4BaseIdBaseSpell, tierIndex
    - ravelInstanceId, castTime, spellDuration, spellCoolDown
    - targetMinRange, targetMaxRange, and many more
    """
    return {
        'id': record.get('ID', 0),
        'description': record.get('description', ''),
        'base_spell_id': record.get('spell4BaseIdBaseSpell', 0),
        'tier_index': record.get('tierIndex', 1),
        'cast_time': record.get('castTime', 0),
        'duration': record.get('spellDuration', 0),
        'cooldown': record.get('spellCoolDown', 0),
        'min_range': record.get('targetMinRange', 0.0),
        'max_range': record.get('targetMaxRange', 0.0),
        'ravel_instance_id': record.get('ravelInstanceId', 0),
    }


def should_include_item(record: dict) -> bool:
    """Filter items to include."""
    return record.get('ID', 0) > 0


def transform_item(record: dict) -> dict:
    """Transform item record to Bezgelor format.

    Actual fields from Item2.tbl:
    - ID, itemBudgetId, itemStatId, itemRuneInstanceId, itemQualityId
    - itemSpecialId00, itemImbuementId, item2FamilyId, item2CategoryId
    - item2TypeId, itemDisplayId, itemSourceId, classRequired, raceRequired
    - faction2IdRequired, powerLevel, requiredLevel, requiredItemLevel
    - prerequisiteId, equippedSlotFlags, maxStackCount, maxCharges
    - flags, bindFlags, localizedTextIdName, localizedTextIdTooltip
    """
    return {
        'id': record.get('ID', 0),
        'name_text_id': record.get('localizedTextIdName', 0),
        'tooltip_text_id': record.get('localizedTextIdTooltip', 0),
        'family_id': record.get('item2FamilyId', 0),
        'category_id': record.get('item2CategoryId', 0),
        'type_id': record.get('item2TypeId', 0),
        'quality_id': record.get('itemQualityId', 0),
        'display_id': record.get('itemDisplayId', 0),
        'power_level': record.get('powerLevel', 0),
        'required_level': record.get('requiredLevel', 0),
        'required_item_level': record.get('requiredItemLevel', 0),
        'class_required': record.get('classRequired', 0),
        'race_required': record.get('raceRequired', 0),
        'faction_required': record.get('faction2IdRequired', 0),
        'equipped_slot_flags': record.get('equippedSlotFlags', 0),
        'max_stack_count': record.get('maxStackCount', 1),
        'max_charges': record.get('maxCharges', 0),
        'flags': record.get('flags', 0),
        'bind_flags': record.get('bindFlags', 0),
        'stat_id': record.get('itemStatId', 0),
        'budget_id': record.get('itemBudgetId', 0),
    }


def extract_table(tbl_path: Path, config: dict, output_dir: Path) -> bool:
    """Extract and transform a single table."""
    try:
        print(f"Extracting {tbl_path.name}...")

        extractor = TblExtractor(str(tbl_path))
        records = extractor.extract()

        print(f"  Found {len(records)} raw records")

        # Transform records
        transformed = config['transform'](records)
        print(f"  Transformed to {len(transformed)} records")

        # Write output
        output_path = output_dir / config['output']
        output_data = {config['key']: transformed}

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(output_data, f, indent=2, ensure_ascii=False)

        print(f"  Wrote {output_path}")
        return True

    except FileNotFoundError:
        print(f"  Not found: {tbl_path}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"  Error: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Extract WildStar game data for Bezgelor'
    )
    parser.add_argument('tbl_dir', help='Directory containing .tbl files')
    parser.add_argument(
        'output_dir',
        nargs='?',
        help='Output directory (default: ../../apps/bezgelor_data/priv/data/)'
    )

    args = parser.parse_args()

    tbl_dir = Path(args.tbl_dir)
    if not tbl_dir.exists():
        print(f"Error: TBL directory not found: {tbl_dir}", file=sys.stderr)
        sys.exit(1)

    if args.output_dir:
        output_dir = Path(args.output_dir)
    else:
        # Default to bezgelor_data priv/data
        script_dir = Path(__file__).parent
        output_dir = script_dir / '../../apps/bezgelor_data/priv/data'

    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"TBL source: {tbl_dir}")
    print(f"Output: {output_dir}")
    print()

    success = 0
    failed = 0

    for tbl_name, config in TABLE_CONFIG.items():
        tbl_path = tbl_dir / tbl_name
        if extract_table(tbl_path, config, output_dir):
            success += 1
        else:
            failed += 1

    print()
    print(f"Complete: {success} succeeded, {failed} failed")

    if failed > 0:
        print("\nNote: Missing tables is normal - not all tables may be present")
        print("in your .tbl extraction. The server will use placeholder data.")


if __name__ == '__main__':
    main()
