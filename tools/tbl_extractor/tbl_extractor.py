#!/usr/bin/env python3
"""
WildStar .tbl (ClientDB) File Extractor

Extracts data from WildStar's .tbl game table files and exports to JSON.
Based on reverse engineering from the NexusForever project.

Usage:
    python tbl_extractor.py <input.tbl> [output.json]
    python tbl_extractor.py --batch <input_dir> <output_dir>

Requirements:
    Python 3.8+
    No external dependencies required.
"""

import argparse
import json
import os
import struct
import sys
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Any, BinaryIO, Dict, List, Optional, Tuple


class DataType(IntEnum):
    """Data types used in WildStar .tbl files."""
    UINT = 3       # 4 bytes, unsigned 32-bit integer
    FLOAT = 4      # 4 bytes, IEEE 754 float
    BOOL = 11      # 4 bytes, boolean as uint32
    ULONG = 20     # 8 bytes, unsigned 64-bit integer
    STRING = 130   # 8 bytes, two uint32 offsets into string table


@dataclass
class GameTableHeader:
    """Header structure for .tbl files (104 bytes)."""
    signature: int       # 4 bytes - 0x4C424454 ("TBLD" little-endian, "LBDT" in memory)
    version: int         # 4 bytes
    name_length: int     # 8 bytes
    unknown1: int        # 8 bytes
    record_size: int     # 8 bytes - size of each record in bytes
    field_count: int     # 8 bytes - number of fields per record
    field_offset: int    # 8 bytes - offset to field definitions
    record_count: int    # 8 bytes - number of records
    total_record_size: int  # 8 bytes - total size of all records + strings
    record_offset: int   # 8 bytes - offset to record data
    max_id: int          # 8 bytes
    lookup_offset: int   # 8 bytes
    unknown2: int        # 8 bytes

    STRUCT_FORMAT = '<II QQQQQQQQQQ Q'  # 104 bytes total
    STRUCT_SIZE = struct.calcsize(STRUCT_FORMAT)

    @classmethod
    def from_bytes(cls, data: bytes) -> 'GameTableHeader':
        values = struct.unpack(cls.STRUCT_FORMAT, data[:cls.STRUCT_SIZE])
        return cls(
            signature=values[0],
            version=values[1],
            name_length=values[2],
            unknown1=values[3],
            record_size=values[4],
            field_count=values[5],
            field_offset=values[6],
            record_count=values[7],
            total_record_size=values[8],
            record_offset=values[9],
            max_id=values[10],
            lookup_offset=values[11],
            unknown2=values[12],
        )


@dataclass
class GameTableField:
    """Field definition structure (24 bytes)."""
    name_length: int     # 8 bytes
    name_offset: int     # 8 bytes
    data_type: DataType  # 2 bytes
    unknown2: int        # 2 bytes
    unknown3: int        # 4 bytes
    name: str = ""       # Resolved name

    STRUCT_FORMAT = '<QQ H H I'  # 24 bytes
    STRUCT_SIZE = struct.calcsize(STRUCT_FORMAT)

    @classmethod
    def from_bytes(cls, data: bytes) -> 'GameTableField':
        values = struct.unpack(cls.STRUCT_FORMAT, data[:cls.STRUCT_SIZE])
        return cls(
            name_length=values[0],
            name_offset=values[1],
            data_type=DataType(values[2]) if values[2] in DataType._value2member_map_ else values[2],
            unknown2=values[3],
            unknown3=values[4],
        )


class TblExtractor:
    """Extracts data from WildStar .tbl files."""

    SIGNATURE = 0x4454424C  # "LBTD" as little-endian uint32

    def __init__(self, filepath: str):
        self.filepath = filepath
        self.header: Optional[GameTableHeader] = None
        self.fields: List[GameTableField] = []
        self.records: List[Dict[str, Any]] = []
        self._data: bytes = b''
        self._string_table_offset: int = 0

    def extract(self) -> List[Dict[str, Any]]:
        """Extract all records from the .tbl file."""
        with open(self.filepath, 'rb') as f:
            self._data = f.read()

        self._read_header()
        self._read_fields()
        self._read_records()

        return self.records

    def _read_header(self):
        """Read and validate the file header."""
        if len(self._data) < GameTableHeader.STRUCT_SIZE:
            raise ValueError(f"File too small: {len(self._data)} bytes")

        self.header = GameTableHeader.from_bytes(self._data)

        if self.header.signature != self.SIGNATURE:
            raise ValueError(
                f"Invalid signature: 0x{self.header.signature:08X} "
                f"(expected 0x{self.SIGNATURE:08X})"
            )

        # Calculate string table offset
        records_end = (
            GameTableHeader.STRUCT_SIZE +
            self.header.record_offset +
            (self.header.record_size * self.header.record_count)
        )
        self._string_table_offset = records_end

    def _read_fields(self):
        """Read field definitions."""
        field_start = GameTableHeader.STRUCT_SIZE + self.header.field_offset

        # Field names are stored in UTF-16LE after field definitions, 16-byte aligned
        field_end = field_start + (self.header.field_count * GameTableField.STRUCT_SIZE)
        # Align to 16-byte boundary
        field_name_base = (field_end + 15) & ~15

        for i in range(self.header.field_count):
            offset = field_start + (i * GameTableField.STRUCT_SIZE)
            field = GameTableField.from_bytes(self._data[offset:])

            # Read field name from the field name table (UTF-16LE encoded)
            if field.name_length > 0:
                name_start = field_name_base + field.name_offset
                # name_length is character count, UTF-16LE uses 2 bytes per char
                name_end = name_start + (field.name_length * 2)
                if name_end <= len(self._data):
                    try:
                        field.name = self._data[name_start:name_end].decode('utf-16-le').rstrip('\x00')
                    except UnicodeDecodeError:
                        field.name = f"field_{i}"
                else:
                    field.name = f"field_{i}"
            else:
                field.name = f"field_{i}"

            # Use index as name if empty
            if not field.name:
                field.name = f"field_{i}"

            self.fields.append(field)

    def _read_records(self):
        """Read all records."""
        record_start = GameTableHeader.STRUCT_SIZE + self.header.record_offset

        for i in range(self.header.record_count):
            offset = record_start + (i * self.header.record_size)
            record = self._read_record(offset)
            self.records.append(record)

    def _read_record(self, offset: int) -> Dict[str, Any]:
        """Read a single record at the given offset."""
        record = {}
        field_offset = offset

        for field in self.fields:
            value, size = self._read_field_value(field_offset, field.data_type)
            record[field.name] = value
            field_offset += size

        return record

    def _read_field_value(self, offset: int, data_type: DataType) -> Tuple[Any, int]:
        """Read a field value and return (value, bytes_consumed)."""
        # Check if it's NOT a valid DataType enum (raw int from unknown type)
        if not isinstance(data_type, DataType):
            # Unknown data type - skip 4 bytes as default
            return None, 4

        if data_type == DataType.UINT:
            value = struct.unpack_from('<I', self._data, offset)[0]
            return value, 4

        elif data_type == DataType.FLOAT:
            value = struct.unpack_from('<f', self._data, offset)[0]
            # Round to reasonable precision
            return round(value, 6), 4

        elif data_type == DataType.BOOL:
            value = struct.unpack_from('<I', self._data, offset)[0]
            return value != 0, 4

        elif data_type == DataType.ULONG:
            value = struct.unpack_from('<Q', self._data, offset)[0]
            return value, 8

        elif data_type == DataType.STRING:
            # Two uint32 offsets - use the larger one
            offset1, offset2 = struct.unpack_from('<II', self._data, offset)
            string_offset = max(offset1, offset2)

            if string_offset > 0:
                string_start = self._string_table_offset + string_offset
                # Read null-terminated string
                string_end = self._data.find(b'\x00', string_start)
                if string_end == -1:
                    string_end = len(self._data)
                try:
                    value = self._data[string_start:string_end].decode('utf-8')
                except UnicodeDecodeError:
                    value = ""
            else:
                value = ""

            return value, 8

        else:
            # Unknown type - assume 4 bytes
            return None, 4

    def get_info(self) -> Dict[str, Any]:
        """Get metadata about the .tbl file."""
        if not self.header:
            self.extract()

        return {
            'file': os.path.basename(self.filepath),
            'version': self.header.version,
            'record_count': self.header.record_count,
            'field_count': self.header.field_count,
            'record_size': self.header.record_size,
            'fields': [
                {
                    'name': f.name,
                    'type': f.data_type.name if isinstance(f.data_type, DataType) else f'UNKNOWN({f.data_type})'
                }
                for f in self.fields
            ]
        }


def extract_single(input_path: str, output_path: Optional[str] = None, verbose: bool = False) -> bool:
    """Extract a single .tbl file to JSON."""
    try:
        extractor = TblExtractor(input_path)

        if verbose:
            info = extractor.get_info()
            print(f"File: {info['file']}")
            print(f"  Version: {info['version']}")
            print(f"  Records: {info['record_count']}")
            print(f"  Fields: {info['field_count']}")
            for f in info['fields']:
                print(f"    - {f['name']}: {f['type']}")

        records = extractor.extract()

        if output_path is None:
            output_path = os.path.splitext(input_path)[0] + '.json'

        # Determine the table name from filename
        table_name = os.path.splitext(os.path.basename(input_path))[0].lower()

        # Wrap records in an object with the table name as key
        output_data = {table_name: records}

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(output_data, f, indent=2, ensure_ascii=False)

        print(f"Extracted {len(records)} records to {output_path}")
        return True

    except Exception as e:
        print(f"Error extracting {input_path}: {e}", file=sys.stderr)
        return False


def extract_batch(input_dir: str, output_dir: str, verbose: bool = False) -> Tuple[int, int]:
    """Extract all .tbl files from a directory."""
    input_path = Path(input_dir)
    output_path = Path(output_dir)

    if not input_path.exists():
        print(f"Input directory not found: {input_dir}", file=sys.stderr)
        return 0, 0

    output_path.mkdir(parents=True, exist_ok=True)

    success = 0
    failed = 0

    for tbl_file in input_path.glob('*.tbl'):
        json_file = output_path / (tbl_file.stem + '.json')
        if extract_single(str(tbl_file), str(json_file), verbose):
            success += 1
        else:
            failed += 1

    return success, failed


def main():
    parser = argparse.ArgumentParser(
        description='Extract WildStar .tbl (ClientDB) files to JSON',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s Creature2.tbl                    # Extract to Creature2.json
  %(prog)s Creature2.tbl creatures.json     # Extract to specific file
  %(prog)s --batch ./tbl ./json             # Extract all .tbl files
  %(prog)s --info Creature2.tbl             # Show file info only
        """
    )

    parser.add_argument('input', help='Input .tbl file or directory (with --batch)')
    parser.add_argument('output', nargs='?', help='Output .json file or directory')
    parser.add_argument('--batch', action='store_true', help='Process all .tbl files in directory')
    parser.add_argument('--info', action='store_true', help='Show file info without extracting')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')

    args = parser.parse_args()

    if args.info:
        try:
            extractor = TblExtractor(args.input)
            info = extractor.get_info()
            print(f"File: {info['file']}")
            print(f"Version: {info['version']}")
            print(f"Records: {info['record_count']}")
            print(f"Fields ({info['field_count']}):")
            for f in info['fields']:
                print(f"  - {f['name']}: {f['type']}")
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)

    elif args.batch:
        if not args.output:
            print("Output directory required with --batch", file=sys.stderr)
            sys.exit(1)

        success, failed = extract_batch(args.input, args.output, args.verbose)
        print(f"\nBatch complete: {success} succeeded, {failed} failed")

        if failed > 0:
            sys.exit(1)

    else:
        if not extract_single(args.input, args.output, args.verbose):
            sys.exit(1)


if __name__ == '__main__':
    main()
