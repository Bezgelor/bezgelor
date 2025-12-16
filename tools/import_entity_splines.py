#!/usr/bin/env python3
"""
Import entity_spline data from NexusForever.WorldDatabase SQL files.

This extracts the entity spawn positions and their associated spline configurations,
outputting JSON that can be used to match our creature spawns to patrol paths.

Usage:
    python tools/import_entity_splines.py ../NexusForever.WorldDatabase
"""

import os
import re
import json
import sys
from pathlib import Path


def parse_sql_file(filepath):
    """Parse a NexusForever zone SQL file and extract entity + entity_spline data."""

    with open(filepath, 'r') as f:
        content = f.read()

    # Extract world ID
    world_match = re.search(r'SET @WORLD = (\d+);', content)
    if not world_match:
        return None, []

    world_id = int(world_match.group(1))

    # Split into entity blocks (each starts with a comment and SET @GUID)
    blocks = re.split(r'-- -{30,}', content)

    entities_with_splines = []

    for block in blocks:
        # Find entity INSERT
        entity_match = re.search(
            r"INSERT INTO `entity`.*?VALUES\s*(.*?);",
            block, re.DOTALL
        )

        # Find entity_spline INSERT
        spline_match = re.search(
            r"INSERT INTO `entity_spline`.*?VALUES\s*(.*?);",
            block, re.DOTALL
        )

        if not entity_match or not spline_match:
            continue

        # Parse entity rows
        entity_rows = parse_values(entity_match.group(1))

        # Parse spline rows
        spline_rows = parse_values(spline_match.group(1))

        # Build spline lookup by relative GUID offset
        spline_by_offset = {}
        for row in spline_rows:
            # Row format: (@GUID+N, SplineId, Mode, Speed, FX, FY, FZ)
            offset_match = re.search(r'@GUID\+(\d+)', row[0])
            if offset_match:
                offset = int(offset_match.group(1))
                spline_by_offset[offset] = {
                    'spline_id': int(row[1]),
                    'mode': int(row[2]),
                    'speed': float(row[3]),
                    'fx': float(row[4]) if len(row) > 4 else 0,
                    'fy': float(row[5]) if len(row) > 5 else 0,
                    'fz': float(row[6]) if len(row) > 6 else 0,
                }

        # Match entities to splines
        for row in entity_rows:
            # Row format: (@GUID+N, Type, Creature, World, Area, X, Y, Z, RX, RY, RZ, DisplayInfo, ...)
            offset_match = re.search(r'@GUID\+(\d+)', row[0])
            if not offset_match:
                continue

            offset = int(offset_match.group(1))

            if offset not in spline_by_offset:
                continue

            # Extract entity data
            try:
                entity_data = {
                    'world_id': world_id,
                    'creature_id': int(row[2]),
                    'area_id': int(row[4]),
                    'position': [float(row[5]), float(row[6]), float(row[7])],
                    'spline': spline_by_offset[offset]
                }
                entities_with_splines.append(entity_data)
            except (ValueError, IndexError) as e:
                continue

    return world_id, entities_with_splines


def parse_values(values_str):
    """Parse SQL VALUES clause into list of row tuples."""
    rows = []

    # Split by row (each row is in parentheses)
    row_pattern = r'\((.*?)\)'
    for match in re.finditer(row_pattern, values_str):
        row_str = match.group(1)
        # Split by comma, but handle quoted strings
        values = smart_split(row_str)
        rows.append(values)

    return rows


def smart_split(s):
    """Split by comma, respecting quotes and parentheses."""
    values = []
    current = []
    depth = 0
    in_quote = False

    for char in s:
        if char == "'" and depth == 0:
            in_quote = not in_quote
            current.append(char)
        elif char == '(' and not in_quote:
            depth += 1
            current.append(char)
        elif char == ')' and not in_quote:
            depth -= 1
            current.append(char)
        elif char == ',' and depth == 0 and not in_quote:
            values.append(''.join(current).strip())
            current = []
        else:
            current.append(char)

    if current:
        values.append(''.join(current).strip())

    return values


def main():
    if len(sys.argv) < 2:
        print("Usage: python import_entity_splines.py <NexusForever.WorldDatabase path>")
        sys.exit(1)

    db_path = Path(sys.argv[1])
    if not db_path.exists():
        print(f"Error: Path not found: {db_path}")
        sys.exit(1)

    all_entities = []

    # Find all SQL files
    sql_files = list(db_path.glob("**/*.sql"))
    print(f"Found {len(sql_files)} SQL files")

    for sql_file in sql_files:
        world_id, entities = parse_sql_file(sql_file)
        if entities:
            print(f"  {sql_file.name}: world {world_id}, {len(entities)} entities with splines")
            all_entities.extend(entities)

    print(f"\nTotal entities with splines: {len(all_entities)}")

    # Group by world_id for easier lookup
    by_world = {}
    for entity in all_entities:
        world_id = entity['world_id']
        if world_id not in by_world:
            by_world[world_id] = []
        by_world[world_id].append(entity)

    print(f"Worlds with spline data: {sorted(by_world.keys())}")

    # Output JSON
    output_path = Path("apps/bezgelor_data/priv/data/entity_splines.json")
    with open(output_path, 'w') as f:
        json.dump({
            'by_world': by_world,
            'total_count': len(all_entities)
        }, f, indent=2)

    print(f"\nWritten to: {output_path}")

    # Also output a summary by world
    print("\nSummary by world:")
    for world_id in sorted(by_world.keys()):
        entities = by_world[world_id]
        spline_ids = set(e['spline']['spline_id'] for e in entities)
        print(f"  World {world_id}: {len(entities)} entities, {len(spline_ids)} unique splines")


if __name__ == '__main__':
    main()
