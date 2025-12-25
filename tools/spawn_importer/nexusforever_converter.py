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


# NexusForever entity types (from NexusForever.Game.Static.Entity.EntityType)
class EntityType:
    """Entity type constants from NexusForever."""
    NPC = 0           # Non-player character (vendors, quest givers)
    RESOURCE = 5      # Gathering nodes
    OBJECT = 8        # Interactive objects
    CREATURE = 10     # Standard creatures/mobs
    BINDPOINT = 19    # Resurrection/graveyard bindpoints
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


@dataclass
class EntityEvent:
    """Represents entity event trigger (for phased content)."""
    entity_id: int
    event_id: int
    phase: int


@dataclass
class EntityProperty:
    """Represents entity property override."""
    entity_id: int
    property_id: int
    value: float


@dataclass
class EntityScript:
    """Represents entity script binding (for boss AI, special behaviors)."""
    entity_id: int
    script_name: str


@dataclass
class MapEntrance:
    """Represents instance entrance/spawn point."""
    map_id: int
    team: int
    world_location_id: int


@dataclass
class EntityVendor:
    """Represents vendor entity with price multipliers."""
    entity_id: int
    buy_price_multiplier: float
    sell_price_multiplier: float


@dataclass
class EntityVendorCategory:
    """Represents vendor item category."""
    entity_id: int
    index: int
    localized_text_id: int


@dataclass
class EntityVendorItem:
    """Represents item sold by a vendor."""
    entity_id: int
    index: int
    category_index: int
    item_id: int


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

    # Regex for INSERT INTO entity_event VALUES
    EVENT_INSERT_RE = re.compile(
        r"INSERT INTO `entity_event`.*?VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    # Regex for INSERT INTO entity_property VALUES
    PROPERTY_INSERT_RE = re.compile(
        r"INSERT INTO `entity_property`.*?VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    # Regex for INSERT INTO entity_script VALUES
    SCRIPT_INSERT_RE = re.compile(
        r"INSERT INTO `entity_script`.*?VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    # Regex for INSERT INTO map_entrance VALUES (handles both VALUE and VALUES)
    MAP_ENTRANCE_INSERT_RE = re.compile(
        r"INSERT INTO map_entrance.*?VALUES?\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    # Regex for INSERT INTO entity_vendor VALUES
    VENDOR_INSERT_RE = re.compile(
        r"INSERT INTO `entity_vendor`.*?VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    # Regex for INSERT INTO entity_vendor_category VALUES
    VENDOR_CATEGORY_INSERT_RE = re.compile(
        r"INSERT INTO `entity_vendor_category`.*?VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    # Regex for INSERT INTO entity_vendor_item VALUES
    VENDOR_ITEM_INSERT_RE = re.compile(
        r"INSERT INTO `entity_vendor_item`.*?VALUES\s*(.*?);",
        re.IGNORECASE | re.DOTALL
    )

    @classmethod
    def parse_sql_file(cls, filepath: Path) -> Dict[str, List]:
        """Parse a SQL file and extract entity data."""
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        return {
            'entities': cls._parse_entities(content),
            'splines': cls._parse_splines(content),
            'stats': cls._parse_stats(content),
            'events': cls._parse_events(content),
            'properties': cls._parse_properties(content),
            'scripts': cls._parse_scripts(content),
            'map_entrances': cls._parse_map_entrances(content),
            'vendors': cls._parse_vendors(content),
            'vendor_categories': cls._parse_vendor_categories(content),
            'vendor_items': cls._parse_vendor_items(content),
        }

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

                if len(values) >= 15:
                    try:
                        # Handle @GUID+N or literal ID
                        entity_id_counter += 1
                        spawn_id = cls._parse_int_or_var(values[0], entity_id_counter, world_id)

                        # Parse optional fields (QuestChecklistIdx at index 15, ActivePropId at index 16)
                        quest_checklist_idx = 0
                        if len(values) > 15 and values[15].strip() not in ('NULL', ''):
                            quest_checklist_idx = cls._parse_int_or_var(values[15], 0, 0)

                        active_prop_id = None
                        if len(values) > 16 and values[16].strip() not in ('NULL', ''):
                            active_prop_id = cls._parse_int_or_var(values[16], 0, 0)

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
                            quest_checklist_idx=quest_checklist_idx,
                            active_prop_id=active_prop_id
                        )
                        entities.append(entity)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse entity: {e}", file=sys.stderr)

        return entities

    @classmethod
    def _parse_splines(cls, content: str) -> List[EntitySpline]:
        """Extract entity spline data from SQL content."""
        splines = []
        entity_id_counter = 0

        for match in cls.SPLINE_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 4:
                    try:
                        entity_id_counter += 1
                        spline = EntitySpline(
                            entity_id=cls._parse_int_or_var(values[0], entity_id_counter, 0),
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
        entity_id_counter = 0

        for match in cls.STATS_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 3:
                    try:
                        entity_id_counter += 1
                        stat = EntityStat(
                            entity_id=cls._parse_int_or_var(values[0], entity_id_counter, 0),
                            stat_id=int(values[1]),
                            value=float(values[2])
                        )
                        stats.append(stat)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse stat: {e}", file=sys.stderr)

        return stats

    @classmethod
    def _parse_events(cls, content: str) -> List[EntityEvent]:
        """Extract entity event data from SQL content."""
        events = []
        entity_id_counter = 0

        # Extract @EVENTID value if set
        event_id = 0
        event_match = re.search(r'SET\s+@EVENTID\s*=\s*(\d+)', content, re.IGNORECASE)
        if event_match:
            event_id = int(event_match.group(1))

        for match in cls.EVENT_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 3:
                    try:
                        entity_id_counter += 1
                        # Handle @EVENTID variable
                        parsed_event_id = event_id
                        if values[1].strip().upper() == '@EVENTID':
                            parsed_event_id = event_id
                        else:
                            parsed_event_id = cls._parse_int_or_var(values[1], 0, 0)

                        event = EntityEvent(
                            entity_id=cls._parse_int_or_var(values[0], entity_id_counter, 0),
                            event_id=parsed_event_id,
                            phase=int(values[2])
                        )
                        events.append(event)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse event: {e}", file=sys.stderr)

        return events

    @classmethod
    def _parse_properties(cls, content: str) -> List[EntityProperty]:
        """Extract entity property data from SQL content."""
        properties = []
        entity_id_counter = 0

        for match in cls.PROPERTY_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 3:
                    try:
                        entity_id_counter += 1
                        prop = EntityProperty(
                            entity_id=cls._parse_int_or_var(values[0], entity_id_counter, 0),
                            property_id=int(values[1]),
                            value=float(values[2])
                        )
                        properties.append(prop)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse property: {e}", file=sys.stderr)

        return properties

    @classmethod
    def _parse_scripts(cls, content: str) -> List[EntityScript]:
        """Extract entity script data from SQL content."""
        scripts = []
        entity_id_counter = 0

        for match in cls.SCRIPT_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 2:
                    try:
                        entity_id_counter += 1
                        # Script name is quoted, strip quotes
                        script_name = values[1].strip().strip("'\"")
                        script = EntityScript(
                            entity_id=cls._parse_int_or_var(values[0], entity_id_counter, 0),
                            script_name=script_name
                        )
                        scripts.append(script)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse script: {e}", file=sys.stderr)

        return scripts

    @classmethod
    def _parse_map_entrances(cls, content: str) -> List[MapEntrance]:
        """Extract map entrance data from SQL content."""
        entrances = []

        # Extract @WORLD value if set
        world_id = 0
        world_match = re.search(r'SET\s+@WORLD\s*=\s*(\d+)', content, re.IGNORECASE)
        if world_match:
            world_id = int(world_match.group(1))

        for match in cls.MAP_ENTRANCE_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 3:
                    try:
                        entrance = MapEntrance(
                            map_id=cls._parse_int_or_var(values[0], 0, world_id),
                            team=int(values[1]),
                            world_location_id=int(values[2])
                        )
                        entrances.append(entrance)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse map entrance: {e}", file=sys.stderr)

        return entrances

    @classmethod
    def _parse_vendors(cls, content: str) -> List[EntityVendor]:
        """Extract entity vendor data from SQL content."""
        vendors = []

        for match in cls.VENDOR_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 3:
                    try:
                        vendor = EntityVendor(
                            entity_id=int(values[0]),
                            buy_price_multiplier=float(values[1]),
                            sell_price_multiplier=float(values[2])
                        )
                        vendors.append(vendor)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse vendor: {e}", file=sys.stderr)

        return vendors

    @classmethod
    def _parse_vendor_categories(cls, content: str) -> List[EntityVendorCategory]:
        """Extract entity vendor category data from SQL content."""
        categories = []

        for match in cls.VENDOR_CATEGORY_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 3:
                    try:
                        category = EntityVendorCategory(
                            entity_id=int(values[0]),
                            index=int(values[1]),
                            localized_text_id=int(values[2])
                        )
                        categories.append(category)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse vendor category: {e}", file=sys.stderr)

        return categories

    @classmethod
    def _parse_vendor_items(cls, content: str) -> List[EntityVendorItem]:
        """Extract entity vendor item data from SQL content."""
        items = []

        for match in cls.VENDOR_ITEM_INSERT_RE.finditer(content):
            values_block = match.group(1)

            for tuple_match in cls.VALUE_TUPLE_RE.finditer(values_block):
                values_str = tuple_match.group(1)
                values = cls._parse_values(values_str)

                if len(values) >= 4:
                    try:
                        item = EntityVendorItem(
                            entity_id=int(values[0]),
                            index=int(values[1]),
                            category_index=int(values[2]),
                            item_id=int(values[3])
                        )
                        items.append(item)
                    except (ValueError, IndexError) as e:
                        print(f"Warning: Failed to parse vendor item: {e}", file=sys.stderr)

        return items

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
    parsed_data: Dict[str, List],
    zone_name: str
) -> Dict[str, Any]:
    """Convert parsed data to Bezgelor JSON format."""

    entities = parsed_data['entities']
    splines = parsed_data['splines']
    stats = parsed_data['stats']
    events = parsed_data['events']
    properties = parsed_data['properties']
    scripts = parsed_data['scripts']
    map_entrances = parsed_data['map_entrances']
    vendors = parsed_data['vendors']
    vendor_categories = parsed_data['vendor_categories']
    vendor_items = parsed_data['vendor_items']

    # Build lookup tables
    spline_by_entity = {s.entity_id: s for s in splines}
    stats_by_entity: Dict[int, List[EntityStat]] = {}
    for stat in stats:
        if stat.entity_id not in stats_by_entity:
            stats_by_entity[stat.entity_id] = []
        stats_by_entity[stat.entity_id].append(stat)

    events_by_entity: Dict[int, List[EntityEvent]] = {}
    for event in events:
        if event.entity_id not in events_by_entity:
            events_by_entity[event.entity_id] = []
        events_by_entity[event.entity_id].append(event)

    properties_by_entity: Dict[int, List[EntityProperty]] = {}
    for prop in properties:
        if prop.entity_id not in properties_by_entity:
            properties_by_entity[prop.entity_id] = []
        properties_by_entity[prop.entity_id].append(prop)

    scripts_by_entity = {s.entity_id: s for s in scripts}

    # Build vendor lookup tables
    vendor_by_entity = {v.entity_id: v for v in vendors}
    categories_by_vendor: Dict[int, List[EntityVendorCategory]] = {}
    for cat in vendor_categories:
        if cat.entity_id not in categories_by_vendor:
            categories_by_vendor[cat.entity_id] = []
        categories_by_vendor[cat.entity_id].append(cat)
    items_by_vendor: Dict[int, List[EntityVendorItem]] = {}
    for item in vendor_items:
        if item.entity_id not in items_by_vendor:
            items_by_vendor[item.entity_id] = []
        items_by_vendor[item.entity_id].append(item)

    # Group entities by world_id (zone)
    by_world: Dict[int, List[EntitySpawn]] = {}
    for entity in entities:
        if entity.world_id not in by_world:
            by_world[entity.world_id] = []
        by_world[entity.world_id].append(entity)

    # Ensure worlds from map_entrances are included even without entities
    for entrance in map_entrances:
        if entrance.map_id not in by_world:
            by_world[entrance.map_id] = []

    # Build output structure
    zone_spawns = []

    for world_id, world_entities in sorted(by_world.items()):
        # Separate by entity type
        creatures = [e for e in world_entities if e.entity_type in (EntityType.NPC, EntityType.CREATURE)]
        resources = [e for e in world_entities if e.entity_type == EntityType.RESOURCE]
        objects = [e for e in world_entities if e.entity_type == EntityType.OBJECT]
        bindpoints = [e for e in world_entities if e.entity_type == EntityType.BINDPOINT]

        zone_data = {
            "world_id": world_id,
            "zone_name": zone_name,
            "creature_spawns": [],
            "resource_spawns": [],
            "object_spawns": [],
            "bindpoint_spawns": [],
            "map_entrances": [],
            "vendors": []
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

            # Add event triggers if present
            if entity.id in events_by_entity:
                spawn["events"] = [
                    {"event_id": e.event_id, "phase": e.phase}
                    for e in events_by_entity[entity.id]
                ]

            # Add properties if present
            if entity.id in properties_by_entity:
                spawn["properties"] = [
                    {"property_id": p.property_id, "value": p.value}
                    for p in properties_by_entity[entity.id]
                ]

            # Add script binding if present
            if entity.id in scripts_by_entity:
                spawn["script_name"] = scripts_by_entity[entity.id].script_name

            # Add vendor data if present
            if entity.id in vendor_by_entity:
                vendor = vendor_by_entity[entity.id]
                spawn["vendor"] = {
                    "buy_price_multiplier": vendor.buy_price_multiplier,
                    "sell_price_multiplier": vendor.sell_price_multiplier,
                    "categories": [
                        {"index": c.index, "localized_text_id": c.localized_text_id}
                        for c in categories_by_vendor.get(entity.id, [])
                    ],
                    "items": [
                        {"index": i.index, "category_index": i.category_index, "item_id": i.item_id}
                        for i in items_by_vendor.get(entity.id, [])
                    ]
                }

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

        # Process bindpoint (resurrection/graveyard) spawns
        for entity in bindpoints:
            zone_data["bindpoint_spawns"].append({
                "id": entity.id,
                "bindpoint_id": entity.creature_id,  # Links to bind_points.json
                "position": entity.position,
                "rotation": entity.rotation,
                "area_id": entity.area_id,
                "faction1": entity.faction1,
                "faction2": entity.faction2
            })

        # Process map entrances (instance spawn points)
        for entrance in map_entrances:
            if entrance.map_id == world_id:
                zone_data["map_entrances"].append({
                    "team": entrance.team,
                    "world_location_id": entrance.world_location_id
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

    parsed_data = SQLParser.parse_sql_file(input_path)
    zone_name = input_path.stem  # Use filename without extension

    entities = parsed_data['entities']
    print(f"  Found {len(entities)} entities, {len(parsed_data['splines'])} splines, {len(parsed_data['stats'])} stats")
    print(f"  Additional: {len(parsed_data['events'])} events, {len(parsed_data['properties'])} properties, "
          f"{len(parsed_data['scripts'])} scripts, {len(parsed_data['map_entrances'])} map_entrances")
    print(f"  Vendors: {len(parsed_data['vendors'])} vendors, {len(parsed_data['vendor_categories'])} categories, "
          f"{len(parsed_data['vendor_items'])} items")

    # Count by type
    creatures = sum(1 for e in entities if e.entity_type in (EntityType.NPC, EntityType.CREATURE))
    resources = sum(1 for e in entities if e.entity_type == EntityType.RESOURCE)
    objects = sum(1 for e in entities if e.entity_type == EntityType.OBJECT)
    bindpoints = sum(1 for e in entities if e.entity_type == EntityType.BINDPOINT)
    print(f"  Breakdown: {creatures} creatures, {resources} resources, {objects} objects, {bindpoints} bindpoints")

    result = convert_to_bezgelor_format(parsed_data, zone_name)

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
        parsed_data = SQLParser.parse_sql_file(sql_file)
        zone_name = sql_file.stem

        if parsed_data['entities']:
            result = convert_to_bezgelor_format(parsed_data, zone_name)
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
            merged[world_id]["bindpoint_spawns"].extend(zone["bindpoint_spawns"])
            merged[world_id]["map_entrances"].extend(zone["map_entrances"])
            # Note: vendors are per-entity, already included in creature_spawns

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
    total_bindpoints = sum(len(z["bindpoint_spawns"]) for z in merged.values())
    total_entrances = sum(len(z["map_entrances"]) for z in merged.values())
    print(f"Total spawns: {total_creatures} creatures, {total_resources} resources, {total_objects} objects, {total_bindpoints} bindpoints")
    print(f"Total map entrances: {total_entrances}")


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
