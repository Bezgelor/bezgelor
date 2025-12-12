#!/usr/bin/env python3
"""
NexusForever WorldDatabase Spawn Data Converter

Converts NexusForever SQL entity spawn data to Bezgelor JSON format.
Downloads and parses SQL files from the NexusForever.WorldDatabase repository.

Usage:
    python nexusforever_converter.py --download            # Download all SQL files
    python nexusforever_converter.py <input.sql> [output.json]
    python nexusforever_converter.py --batch <input_dir> <output_dir>
    python nexusforever_converter.py --merge <input_dir> <output.json>

Requirements:
    Python 3.8+
    requests (for --download)
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


# NexusForever entity types
class EntityType:
    """Entity type constants from NexusForever."""
    NPC = 0           # Non-player character (vendors, quest givers)
    RESOURCE = 5      # Gathering nodes
    OBJECT = 8        # Interactive objects
    CREATURE = 10     # Standard creatures/mobs
    STRUCTURE = 32    # Buildings, collision objects


@dataclass
class EntitySpawn:
    """Represents a single entity spawn point."""
    id: int
    entity_type: int
    creature_id: int
    world_id: int
    area_id: int
    x: float
    y: float
    z: float
    rx: float
    ry: float
    rz: float
    display_info: int
    outfit_info: int
    faction1: int
    faction2: int
    quest_checklist_idx: int
    active_prop_id: Optional[int] = None

    @property
    def position(self) -> List[float]:
        return [self.x, self.y, self.z]

    @property
    def rotation(self) -> List[float]:
        return [self.rx, self.ry, self.rz]

    def to_spawn_dict(self) -> Dict[str, Any]:
        """Convert to Bezgelor spawn format."""
        return {
            "id": self.id,
            "creature_id": self.creature_id,
            "position": self.position,
            "rotation": self.rotation,
            "area_id": self.area_id,
            "display_info": self.display_info,
            "outfit_info": self.outfit_info,
            "faction1": self.faction1,
            "faction2": self.faction2,
            "respawn_time_ms": 300000,  # Default 5 minute respawn
            "patrol_path_id": None
        }


@dataclass
class EntitySpline:
    """Represents entity movement spline data."""
    entity_id: int
    spline_id: int
    spline_mode: int
    speed: float


@dataclass
class EntityStat:
    """Represents entity stat override."""
    entity_id: int
    stat_id: int
    value: float


class SQLParser:
    """Parses NexusForever SQL dump files."""

    # Regex for INSERT INTO entity VALUES
    ENTITY_INSERT_RE = re.compile(
        r"INSERT INTO `entity`.*?VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    # Regex for individual value tuples
    VALUE_TUPLE_RE = re.compile(
        r"\(([^)]+)\)",
        re.DOTALL
    )

    # Regex for INSERT INTO entity_spline VALUES
    SPLINE_INSERT_RE = re.compile(
        r"INSERT INTO `entity_spline`.*?VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    # Regex for INSERT INTO entity_stats VALUES
    STATS_INSERT_RE = re.compile(
        r"INSERT INTO `entity_stats`.*?VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    @classmethod
    def parse_sql_file(cls, filepath: Path) -> Tuple[List[EntitySpawn], List[EntitySpline], List[EntityStat]]:
        """Parse a SQL file and extract entity data."""
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        entities = cls._parse_entities(content)
        splines = cls._parse_splines(content)
        stats = cls._parse_stats(content)

        return entities, splines, stats

    # Regex for @GUID+N pattern
    GUID_VAR_RE = re.compile(r'@GUID\s*\+\s*(\d+)', re.IGNORECASE)
    # Regex for @WORLD variable
    WORLD_VAR_RE = re.compile(r'@WORLD', re.IGNORECASE)

    @classmethod
    def _parse_int_or_var(cls, value: str, base_id: int = 0, world_id: int = 0) -> int:
        """Parse an integer value, handling @GUID+N and @WORLD variables."""
        value = value.strip()

        # Check for @GUID+N pattern
        guid_match = cls.GUID_VAR_RE.match(value)
        if guid_match:
            return base_id + int(guid_match.group(1))

        # Check for @WORLD variable
        if cls.WORLD_VAR_RE.match(value):
            return world_id

        # Try parsing as regular integer
        return int(value)

    @classmethod
    def _parse_entities(cls, content: str) -> List[EntitySpawn]:
        """Extract entity spawn data from SQL content."""
        entities = []
        entity_id_counter = 0

        # Extract @WORLD value if set
        world_id = 0
        world_match = re.search(r'SET\s+@WORLD\s*=\s*(\d+)', content, re.IGNORECASE)
        if world_match:
            world_id = int(world_match.group(1))

        for match in cls.ENTITY_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 16:
                    try:
                        # Handle @GUID+N or literal ID
                        entity_id_counter += 1
                        spawn_id = cls._parse_int_or_var(values[0], entity_id_counter, world_id)

                        entity = EntitySpawn(
                            id=spawn_id,
                            entity_type=int(values[1]),
                            creature_id=int(values[2]),
                            world_id=cls._parse_int_or_var(values[3], 0, world_id),
                            area_id=int(values[4]),
                            x=float(values[5]),
                            y=float(values[6]),
                            z=float(values[7]),
                            rx=float(values[8]),
                            ry=float(values[9]),
                            rz=float(values[10]),
                            display_info=int(values[11]),
                            outfit_info=int(values[12]),
                            faction1=int(values[13]),
                            faction2=int(values[14]),
                            quest_checklist_idx=cls._parse_int_or_var(values[15], 0, 0) if values[15].strip() not in ('NULL', '') else 0,
                            active_prop_id=cls._parse_int_or_var(values[16], 0, 0) if len(values) > 16 and values[16].strip() not in ('NULL', '') else None
                        )
                        entities.append(entity)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse entity: {e}", file=sys.stderr)

        return entities

    @classmethod
    def _parse_splines(cls, content: str) -> List[EntitySpline]:
        """Extract entity spline data from SQL content."""
        splines = []

        for match in cls.SPLINE_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 4:
                    try:
                        spline = EntitySpline(
                            entity_id=int(values[0]),
                            spline_id=int(values[1]),
                            spline_mode=int(values[2]),
                            speed=float(values[3])
                        )
                        splines.append(spline)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse spline: {e}", file=sys.stderr)

        return splines

    @classmethod
    def _parse_stats(cls, content: str) -> List[EntityStat]:
        """Extract entity stat data from SQL content."""
        stats = []

        for match in cls.STATS_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 3:
                    try:
                        stat = EntityStat(
                            entity_id=int(values[0]),
                            stat_id=int(values[1]),
                            value=float(values[2])
                        )
                        stats.append(stat)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse stat: {e}", file=sys.stderr)

        return stats

    @staticmethod
    def _parse_values(values_str: str) -> List[str]:
        """Parse comma-separated values, handling quoted strings."""
        values = []
        current = ""
        in_string = False

        for char in values_str:
            if char == "'" and not in_string:
                in_string = True
            elif char == "'" and in_string:
                in_string = False
            elif char == "," and not in_string:
                values.append(current.strip())
                current = ""
            else:
                current += char

        if current.strip():
            values.append(current.strip())

        return values


def convert_to_bezgelor_format(
    entities: List[EntitySpawn],
    splines: List[EntitySpline],
    stats: List[EntityStat],
    zone_name: str
) -> Dict[str, Any]:
    """Convert parsed data to Bezgelor JSON format."""

    # Build lookup tables
    spline_by_entity = {s.entity_id: s for s in splines}
    stats_by_entity: Dict[int, List[EntityStat]] = {}
    for stat in stats:
        if stat.entity_id not in stats_by_entity:
            stats_by_entity[stat.entity_id] = []
        stats_by_entity[stat.entity_id].append(stat)

    # Group entities by world_id (zone)
    by_world: Dict[int, List[EntitySpawn]] = {}
    for entity in entities:
        if entity.world_id not in by_world:
            by_world[entity.world_id] = []
        by_world[entity.world_id].append(entity)

    # Build output structure
    zone_spawns = []

    for world_id, world_entities in sorted(by_world.items()):
        # Separate by entity type
        creatures = [e for e in world_entities if e.entity_type in (EntityType.NPC, EntityType.CREATURE)]
        resources = [e for e in world_entities if e.entity_type == EntityType.RESOURCE]
        objects = [e for e in world_entities if e.entity_type == EntityType.OBJECT]

        zone_data = {
            "world_id": world_id,
            "zone_name": zone_name,
            "creature_spawns": [],
            "resource_spawns": [],
            "object_spawns": []
        }

        # Process creature spawns
        for entity in creatures:
            spawn = entity.to_spawn_dict()

            # Add spline if present
            if entity.id in spline_by_entity:
                spline = spline_by_entity[entity.id]
                spawn["patrol_path_id"] = spline.spline_id
                spawn["patrol_speed"] = spline.speed
                spawn["patrol_mode"] = spline.spline_mode

            # Add stat overrides if present
            if entity.id in stats_by_entity:
                spawn["stat_overrides"] = [
                    {"stat_id": s.stat_id, "value": s.value}
                    for s in stats_by_entity[entity.id]
                ]

            zone_data["creature_spawns"].append(spawn)

        # Process resource nodes
        for entity in resources:
            zone_data["resource_spawns"].append({
                "id": entity.id,
                "resource_id": entity.creature_id,
                "position": entity.position,
                "rotation": entity.rotation,
                "area_id": entity.area_id,
                "respawn_time_ms": 180000  # 3 minute respawn for resources
            })

        # Process interactive objects
        for entity in objects:
            zone_data["object_spawns"].append({
                "id": entity.id,
                "object_id": entity.creature_id,
                "position": entity.position,
                "rotation": entity.rotation,
                "area_id": entity.area_id,
                "display_info": entity.display_info,
                "faction1": entity.faction1,
                "faction2": entity.faction2
            })

        zone_spawns.append(zone_data)

    return {
        "source": "NexusForever.WorldDatabase",
        "zone_spawns": zone_spawns
    }


def download_world_database(output_dir: Path):
    """Download SQL files from NexusForever.WorldDatabase repository."""
    try:
        import requests
    except ImportError:
        print("Error: requests library required for download. Install with: pip install requests")
        sys.exit(1)

    BASE_URL = "https://api.github.com/repos/NexusForever/NexusForever.WorldDatabase/contents"
    RAW_BASE = "https://raw.githubusercontent.com/NexusForever/NexusForever.WorldDatabase/master"

    continents = ["Alizar", "Isigrol", "Olyssia", "Instance"]

    output_dir.mkdir(parents=True, exist_ok=True)

    for continent in continents:
        print(f"Fetching {continent}...")
        continent_dir = output_dir / continent
        continent_dir.mkdir(exist_ok=True)

        try:
            response = requests.get(f"{BASE_URL}/{continent}")
            response.raise_for_status()
            files = response.json()

            for file_info in files:
                if file_info["name"].endswith(".sql"):
                    print(f"  Downloading {file_info['name']}...")
                    sql_response = requests.get(f"{RAW_BASE}/{continent}/{file_info['name']}")
                    sql_response.raise_for_status()

                    output_path = continent_dir / file_info["name"]
                    with open(output_path, "w", encoding="utf-8") as f:
                        f.write(sql_response.text)

        except requests.RequestException as e:
            print(f"  Error fetching {continent}: {e}", file=sys.stderr)


def process_single_file(input_path: Path, output_path: Optional[Path] = None):
    """Process a single SQL file."""
    print(f"Processing {input_path}...")

    entities, splines, stats = SQLParser.parse_sql_file(input_path)
    zone_name = input_path.stem  # Use filename without extension

    print(f"  Found {len(entities)} entities, {len(splines)} splines, {len(stats)} stats")

    # Count by type
    creatures = sum(1 for e in entities if e.entity_type in (EntityType.NPC, EntityType.CREATURE))
    resources = sum(1 for e in entities if e.entity_type == EntityType.RESOURCE)
    objects = sum(1 for e in entities if e.entity_type == EntityType.OBJECT)
    print(f"  Breakdown: {creatures} creatures, {resources} resources, {objects} objects")

    result = convert_to_bezgelor_format(entities, splines, stats, zone_name)

    if output_path is None:
        output_path = input_path.with_suffix(".json")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"  Output: {output_path}")
    return result


def process_batch(input_dir: Path, output_dir: Path):
    """Process all SQL files in a directory tree."""
    output_dir.mkdir(parents=True, exist_ok=True)

    for sql_file in input_dir.rglob("*.sql"):
        relative = sql_file.relative_to(input_dir)
        output_path = output_dir / relative.with_suffix(".json")
        output_path.parent.mkdir(parents=True, exist_ok=True)

        process_single_file(sql_file, output_path)


def merge_to_single_file(input_dir: Path, output_path: Path):
    """Merge all SQL files into a single JSON output."""
    all_zone_spawns = []

    for sql_file in sorted(input_dir.rglob("*.sql")):
        print(f"Processing {sql_file}...")
        entities, splines, stats = SQLParser.parse_sql_file(sql_file)
        zone_name = sql_file.stem

        if entities:
            result = convert_to_bezgelor_format(entities, splines, stats, zone_name)
            all_zone_spawns.extend(result["zone_spawns"])

    # Merge zone spawns with same world_id
    merged: Dict[int, Dict] = {}
    for zone in all_zone_spawns:
        world_id = zone["world_id"]
        if world_id not in merged:
            merged[world_id] = zone
        else:
            merged[world_id]["creature_spawns"].extend(zone["creature_spawns"])
            merged[world_id]["resource_spawns"].extend(zone["resource_spawns"])
            merged[world_id]["object_spawns"].extend(zone["object_spawns"])

    output = {
        "source": "NexusForever.WorldDatabase",
        "zone_spawns": list(merged.values())
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2)

    print(f"\nMerged output: {output_path}")
    print(f"Total zones: {len(merged)}")
    total_creatures = sum(len(z["creature_spawns"]) for z in merged.values())
    total_resources = sum(len(z["resource_spawns"]) for z in merged.values())
    total_objects = sum(len(z["object_spawns"]) for z in merged.values())
    print(f"Total spawns: {total_creatures} creatures, {total_resources} resources, {total_objects} objects")


def main():
    parser = argparse.ArgumentParser(
        description="Convert NexusForever SQL spawn data to Bezgelor JSON format"
    )

    subparsers = parser.add_subparsers(dest="command")

    # Download command
    download_parser = subparsers.add_parser("download", help="Download WorldDatabase SQL files")
    download_parser.add_argument(
        "-o", "--output",
        type=Path,
        default=Path("nexusforever_sql"),
        help="Output directory for SQL files"
    )

    # Convert single file
    convert_parser = subparsers.add_parser("convert", help="Convert a single SQL file")
    convert_parser.add_argument("input", type=Path, help="Input SQL file")
    convert_parser.add_argument("output", type=Path, nargs="?", help="Output JSON file")

    # Batch convert
    batch_parser = subparsers.add_parser("batch", help="Convert all SQL files in a directory")
    batch_parser.add_argument("input_dir", type=Path, help="Input directory")
    batch_parser.add_argument("output_dir", type=Path, help="Output directory")

    # Merge to single file
    merge_parser = subparsers.add_parser("merge", help="Merge all SQL files to single JSON")
    merge_parser.add_argument("input_dir", type=Path, help="Input directory")
    merge_parser.add_argument("output", type=Path, help="Output JSON file")

    args = parser.parse_args()

    if args.command == "download":
        download_world_database(args.output)
    elif args.command == "convert":
        process_single_file(args.input, args.output)
    elif args.command == "batch":
        process_batch(args.input_dir, args.output_dir)
    elif args.command == "merge":
        merge_to_single_file(args.input_dir, args.output)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
