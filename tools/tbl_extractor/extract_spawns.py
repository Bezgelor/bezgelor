#!/usr/bin/env python3
"""
Extract spawn data from NexusForever WorldDatabase SQL files.

Parses INSERT statements from SQL files and converts to JSON format
compatible with Bezgelor's creature_spawns.json structure.
"""

import os
import re
import json
import sys
from pathlib import Path

# Zone name to world_id mapping (from WildStar data)
ZONE_WORLD_IDS = {
    "Algoroc": 51,
    "Auroria": 22,
    "Blighthaven": 1061,
    "Celestion": 51,  # Same continent as Algoroc
    "CrimsonIsle": 870,
    "Deradune": 426,  # Dominion starting
    "Ellevar": 1387,
    "EverstarGrove": 990,
    "Galeras": 93,
    "Illium": 1519,
    "LevianBay": 1387,
    "Malgrave": 1303,
    "NorthernWilds": 426,
    "SouthernGrimvault": 1580,
    "Thayd": 1159,
    "TheDefile": 2072,
    "WesternGrimvault": 1377,
    "Whitevale": 426,
    "Wilderrun": 1519,
    # Instances
    "Deep Space Exploration": 5001,
    "Evil from the Ether": 5002,
    "Fragment Zero": 5003,
    "Gauntlet": 5004,
    "Infestation": 5005,
    "Outpost M13": 5006,
    "Rage Logic": 5007,
    "Space Madness": 5008,
    "The Cryo-Plex": 5101,
    "The Slaughterdome": 5102,
}

def parse_sql_file(filepath):
    """Parse a SQL file and extract entity spawn data."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    zone_name = Path(filepath).stem

    # Try to extract world ID from SET @WORLD statement
    world_match = re.search(r'SET\s+@WORLD\s*=\s*(\d+)', content)
    if world_match:
        world_id = int(world_match.group(1))
    else:
        world_id = ZONE_WORLD_IDS.get(zone_name, 0)

    spawns = []

    # Find all INSERT INTO `entity` statements
    # Pattern matches multi-line INSERT with VALUES
    insert_pattern = re.compile(
        r"INSERT INTO `entity`[^(]*\([^)]+\)\s*VALUES\s*((?:\([^)]+\),?\s*)+)",
        re.IGNORECASE | re.DOTALL
    )

    for match in insert_pattern.finditer(content):
        values_block = match.group(1)

        # Extract individual value tuples
        value_pattern = re.compile(r'\(([^)]+)\)')
        for value_match in value_pattern.finditer(values_block):
            values = value_match.group(1)

            # Parse the values (handling @GUID+N expressions)
            parts = []
            current = ""
            in_string = False
            paren_depth = 0

            for char in values + ',':
                if char == "'" and not in_string:
                    in_string = True
                    current += char
                elif char == "'" and in_string:
                    in_string = False
                    current += char
                elif char == '(' and not in_string:
                    paren_depth += 1
                    current += char
                elif char == ')' and not in_string:
                    paren_depth -= 1
                    current += char
                elif char == ',' and not in_string and paren_depth == 0:
                    parts.append(current.strip())
                    current = ""
                else:
                    current += char

            if len(parts) >= 12:
                try:
                    # Extract key fields
                    # Id, Type, Creature, World, Area, X, Y, Z, RX, RY, RZ, DisplayInfo, ...
                    entity_type = int(parts[1]) if parts[1].isdigit() else 0
                    creature_id = int(parts[2]) if parts[2].isdigit() else 0

                    # Parse coordinates (handle negative numbers)
                    x = float(parts[5].replace(' ', ''))
                    y = float(parts[6].replace(' ', ''))
                    z = float(parts[7].replace(' ', ''))
                    rx = float(parts[8].replace(' ', ''))
                    ry = float(parts[9].replace(' ', ''))
                    rz = float(parts[10].replace(' ', ''))

                    display_info = int(parts[11]) if parts[11].isdigit() else 0

                    # Only include creature spawns (type 0 = creature, type 10 = platform/object)
                    if creature_id > 0:
                        spawn = {
                            "creature_id": creature_id,
                            "position": [x, y, z],
                            "rotation": [rx, ry, rz],
                            "display_info": display_info,
                            "entity_type": entity_type
                        }
                        spawns.append(spawn)
                except (ValueError, IndexError) as e:
                    continue

    return {
        "world_id": world_id,
        "zone_name": zone_name,
        "creature_spawns": [s for s in spawns if s["entity_type"] == 0],
        "resource_spawns": [],  # Would need separate extraction
        "object_spawns": [s for s in spawns if s["entity_type"] != 0]
    }

def extract_all_spawns(db_path, output_path):
    """Extract spawn data from all SQL files in the WorldDatabase."""
    sql_files = list(Path(db_path).rglob("*.sql"))

    print(f"Found {len(sql_files)} SQL files")

    # Group zones by world_id to merge spawns from same continent
    zones_by_world = {}
    total_creatures = 0
    total_objects = 0

    for sql_file in sorted(sql_files):
        print(f"Processing {sql_file.name}...")
        zone_data = parse_sql_file(sql_file)

        creatures = len(zone_data["creature_spawns"])
        objects = len(zone_data["object_spawns"])

        if creatures > 0 or objects > 0:
            world_id = zone_data["world_id"]

            if world_id in zones_by_world:
                # Merge with existing
                existing = zones_by_world[world_id]
                existing["creature_spawns"].extend(zone_data["creature_spawns"])
                existing["object_spawns"].extend(zone_data["object_spawns"])
                existing["resource_spawns"].extend(zone_data["resource_spawns"])
                existing["sub_zones"].append(zone_data["zone_name"])
            else:
                zone_data["sub_zones"] = [zone_data["zone_name"]]
                zones_by_world[world_id] = zone_data

            total_creatures += creatures
            total_objects += objects
            print(f"  -> {zone_data['zone_name']} (world {zone_data['world_id']}): {creatures} creatures, {objects} objects")

    # Convert to list and update zone names to show merged zones
    all_zones = []
    for world_id, zone_data in sorted(zones_by_world.items()):
        if len(zone_data["sub_zones"]) > 1:
            zone_data["zone_name"] = f"{zone_data['sub_zones'][0]} (+{len(zone_data['sub_zones'])-1} more)"
        all_zones.append(zone_data)

    output = {
        "source": "NexusForever.WorldDatabase",
        "zone_spawns": all_zones
    }

    with open(output_path, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"\nExtracted {len(all_zones)} world zones (from {len(sql_files)} zone files):")
    print(f"  Total creatures: {total_creatures}")
    print(f"  Total objects: {total_objects}")
    print(f"  Output: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        db_path = os.path.expanduser("~/work/NexusForever.WorldDatabase")
    else:
        db_path = sys.argv[1]

    if len(sys.argv) >= 3:
        output_path = sys.argv[2]
    else:
        output_path = "apps/bezgelor_data/priv/data/creature_spawns.json"

    if not os.path.exists(db_path):
        print(f"Error: WorldDatabase not found at {db_path}")
        sys.exit(1)

    extract_all_spawns(db_path, output_path)
