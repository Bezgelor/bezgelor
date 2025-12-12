#!/usr/bin/env python3
"""
Generate vendor inventories based on vendor types and item categories.

This script creates a vendor_inventories.json file that maps vendor IDs to
lists of item IDs they should sell.
"""

import json
import os
from collections import defaultdict

# Paths
DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'apps', 'bezgelor_data', 'priv', 'data')
ITEMS_FILE = os.path.join(DATA_DIR, 'items.json')
VENDORS_FILE = os.path.join(DATA_DIR, 'npc_vendors.json')
OUTPUT_FILE = os.path.join(DATA_DIR, 'vendor_inventories.json')

# WildStar item family IDs (from item database)
FAMILY_ARMOR = 1
FAMILY_WEAPON = 2
FAMILY_BAG = 3
FAMILY_HOUSING = 4
FAMILY_CONSUMABLE = 5
FAMILY_MISC = 6
FAMILY_SCHEMATIC = 7
FAMILY_CRAFTING = 8
FAMILY_CURRENCY = 9
FAMILY_MOUNT = 10
FAMILY_PET = 11
FAMILY_COSTUME = 12
FAMILY_TOY = 13
FAMILY_AMP = 14
FAMILY_ABILITY = 15
FAMILY_RUNE = 16
FAMILY_DYE = 17
FAMILY_TOOL = 18

# Item category mappings (approximate - would need full client data for exact mappings)
# These are educated guesses based on typical MMO item categorization
CATEGORY_MAPPING = {
    # Armor categories by slot
    'head': [1, 2],
    'shoulder': [3, 4],
    'chest': [5, 6],
    'hands': [7, 8],
    'legs': [9, 10],
    'feet': [11, 12],
    'shield': [13],
    # Weapon categories
    'sword': [20, 21],
    'axe': [22, 23],
    'mace': [24, 25],
    'pistol': [30],
    'rifle': [31],
    'launcher': [32],
    'psyblade': [35],
    'resonator': [36],
    'claws': [37],
}

# Vendor type to item filter rules
# Each rule specifies: family_ids, quality_min, quality_max, required_level_max
VENDOR_TYPE_RULES = {
    # General goods - consumables, misc items
    'general_goods': {
        'families': [FAMILY_CONSUMABLE, FAMILY_MISC, FAMILY_BAG],
        'quality_range': (0, 2),  # Common to rare
        'level_range': (0, 50),
        'max_items': 50,
    },
    # Armor vendors
    'armor': {
        'families': [FAMILY_ARMOR],
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 100,
    },
    'light_medium_armor': {
        'families': [FAMILY_ARMOR],
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 80,
    },
    'heavy_armor': {
        'families': [FAMILY_ARMOR],
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 80,
    },
    'arcane_armor': {
        'families': [FAMILY_ARMOR],
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 80,
    },
    'tech_armor': {
        'families': [FAMILY_ARMOR],
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 80,
    },
    # Weapon vendors
    'weapons': {
        'families': [FAMILY_WEAPON],
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 100,
    },
    'melee_weapons': {
        'families': [FAMILY_WEAPON],
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 60,
    },
    'ranged_weapons': {
        'families': [FAMILY_WEAPON],
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 60,
    },
    'arcane_weapons': {
        'families': [FAMILY_WEAPON],
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 60,
    },
    # Shields
    'shields': {
        'families': [FAMILY_ARMOR],  # Shields are often in armor family
        'quality_range': (1, 2),
        'level_range': (0, 50),
        'max_items': 30,
    },
    # Consumables vendors
    'consumables': {
        'families': [FAMILY_CONSUMABLE],
        'quality_range': (0, 2),
        'level_range': (0, 50),
        'max_items': 80,
    },
    'potions': {
        'families': [FAMILY_CONSUMABLE],
        'quality_range': (0, 2),
        'level_range': (0, 50),
        'max_items': 40,
    },
    # Tradeskill vendors
    'tradeskill_goods': {
        'families': [FAMILY_CRAFTING, FAMILY_SCHEMATIC, FAMILY_TOOL],
        'quality_range': (0, 2),
        'level_range': (0, 50),
        'max_items': 100,
    },
    'cooking_materials': {
        'families': [FAMILY_CRAFTING],
        'quality_range': (0, 1),
        'level_range': (0, 50),
        'max_items': 50,
    },
    # Mount vendors
    'mounts': {
        'families': [FAMILY_MOUNT],
        'quality_range': (1, 4),
        'level_range': (0, 50),
        'max_items': 30,
    },
    'rented_mounts': {
        'families': [FAMILY_MOUNT],
        'quality_range': (0, 2),
        'level_range': (0, 50),
        'max_items': 20,
    },
    # Companion pets
    'companion_pets': {
        'families': [FAMILY_PET],
        'quality_range': (1, 3),
        'level_range': (0, 50),
        'max_items': 30,
    },
    # Costumes
    'costumes': {
        'families': [FAMILY_COSTUME],
        'quality_range': (1, 3),
        'level_range': (0, 50),
        'max_items': 50,
    },
    # AMPs
    'amps': {
        'families': [FAMILY_AMP],
        'quality_range': (1, 3),
        'level_range': (0, 50),
        'max_items': 100,
    },
    'amp_imports': {
        'families': [FAMILY_AMP],
        'quality_range': (2, 4),
        'level_range': (0, 50),
        'max_items': 50,
    },
    # Dyes
    'dyes': {
        'families': [FAMILY_DYE],
        'quality_range': (0, 3),
        'level_range': (0, 50),
        'max_items': 100,
    },
    # Special vendors - empty or minimal inventories
    'banker': {'families': [], 'max_items': 0},
    'guild_bank': {'families': [], 'max_items': 0},
    'auctioneer': {'families': [], 'max_items': 0},
    'commodity_broker': {'families': [], 'max_items': 0},
    'credd_exchange': {'families': [], 'max_items': 0},
    'ability_trainer': {'families': [FAMILY_ABILITY], 'quality_range': (0, 3), 'level_range': (0, 50), 'max_items': 50},
    'cooking_trainer': {'families': [FAMILY_SCHEMATIC], 'quality_range': (0, 2), 'level_range': (0, 50), 'max_items': 30},
    'farming_trainer': {'families': [FAMILY_SCHEMATIC, FAMILY_TOOL], 'quality_range': (0, 2), 'level_range': (0, 50), 'max_items': 30},
    'fishing_trainer': {'families': [FAMILY_SCHEMATIC, FAMILY_TOOL], 'quality_range': (0, 2), 'level_range': (0, 50), 'max_items': 30},
    'artisan_trainer': {'families': [FAMILY_SCHEMATIC], 'quality_range': (0, 2), 'level_range': (0, 50), 'max_items': 30},
}

# Default rule for unknown vendor types
DEFAULT_RULE = {
    'families': [FAMILY_MISC, FAMILY_CONSUMABLE],
    'quality_range': (0, 2),
    'level_range': (0, 50),
    'max_items': 30,
}


def load_json(filepath):
    """Load JSON file."""
    with open(filepath, 'r') as f:
        return json.load(f)


def filter_items(items, rule):
    """Filter items based on vendor rule."""
    if rule.get('max_items', 0) == 0:
        return []

    families = rule.get('families', [])
    quality_min, quality_max = rule.get('quality_range', (0, 5))
    level_min, level_max = rule.get('level_range', (0, 100))
    max_items = rule.get('max_items', 50)

    filtered = []
    for item in items:
        if families and item.get('family_id') not in families:
            continue
        if not (quality_min <= item.get('quality_id', 0) <= quality_max):
            continue
        if not (level_min <= item.get('required_level', 0) <= level_max):
            continue
        # Skip items with special bind flags (quest items, soulbound, etc.)
        bind_flags = item.get('bind_flags', 0)
        if bind_flags & 1:  # Bind on pickup
            continue
        filtered.append(item)

    # Sort by required level, then by quality
    filtered.sort(key=lambda x: (x.get('required_level', 0), x.get('quality_id', 0)))

    # Return up to max_items
    return filtered[:max_items]


def generate_vendor_inventories():
    """Generate vendor inventory mappings."""
    print("Loading items...")
    items_data = load_json(ITEMS_FILE)
    items = items_data.get('items', [])
    print(f"Loaded {len(items)} items")

    print("Loading vendors...")
    vendors_data = load_json(VENDORS_FILE)
    vendors = vendors_data.get('npc_vendors', [])
    print(f"Loaded {len(vendors)} vendors")

    # Index items by family for faster lookups
    items_by_family = defaultdict(list)
    for item in items:
        items_by_family[item.get('family_id', 0)].append(item)

    print("\nGenerating inventories...")
    vendor_inventories = []
    vendor_type_stats = defaultdict(int)

    for vendor in vendors:
        vendor_id = vendor['id']
        vendor_type = vendor['vendor_type']
        vendor_type_stats[vendor_type] += 1

        # Get rule for this vendor type
        rule = VENDOR_TYPE_RULES.get(vendor_type, DEFAULT_RULE)

        # Get items for this vendor type
        candidate_items = []
        for family_id in rule.get('families', []):
            candidate_items.extend(items_by_family.get(family_id, []))

        # Filter items based on rule
        inventory_items = filter_items(candidate_items, rule)

        # Create inventory entry
        inventory = {
            'vendor_id': vendor_id,
            'creature_id': vendor['creature_id'],
            'vendor_type': vendor_type,
            'items': [
                {
                    'item_id': item['id'],
                    'quantity': -1,  # -1 = unlimited
                    'price_multiplier': 1.0
                }
                for item in inventory_items
            ]
        }
        vendor_inventories.append(inventory)

    print("\nVendor type statistics:")
    for vtype, count in sorted(vendor_type_stats.items(), key=lambda x: -x[1]):
        rule = VENDOR_TYPE_RULES.get(vtype, DEFAULT_RULE)
        max_items = rule.get('max_items', 0)
        print(f"  {vtype}: {count} vendors, max {max_items} items each")

    # Write output
    output = {
        'vendor_inventories': vendor_inventories,
        'metadata': {
            'total_vendors': len(vendors),
            'total_items': len(items),
            'generated_by': 'vendor_inventory_generator.py'
        }
    }

    print(f"\nWriting {len(vendor_inventories)} vendor inventories to {OUTPUT_FILE}...")
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(output, f, indent=2)

    # Stats
    total_inventory_items = sum(len(inv['items']) for inv in vendor_inventories)
    vendors_with_items = sum(1 for inv in vendor_inventories if len(inv['items']) > 0)
    print(f"\nGenerated {total_inventory_items} total item entries")
    print(f"{vendors_with_items}/{len(vendors)} vendors have items")

    return output


if __name__ == '__main__':
    generate_vendor_inventories()
