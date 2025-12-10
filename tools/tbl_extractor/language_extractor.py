#!/usr/bin/env python3
"""
WildStar Language File Extractor

Extracts localized text strings from WildStar's language files (e.g., en-US.bin)
found in the ClientDataEN.archive language pack.

Usage:
    python language_extractor.py <input.bin> [output.json]
    python language_extractor.py --info <input.bin>

The output JSON format is:
    {"texts": {"text_id": "string value", ...}}

Requirements:
    Python 3.8+
    No external dependencies required.

Format Details (reverse-engineered):
    Header:
        0x00: "XETL" magic signature (4 bytes, little-endian)
        0x0C: Locale ID (uint32) - e.g., 1033 for en-US
        0x40: Entry count (uint64) - number of text entries
        0xA0: Index table starts

    Index Table (starts at 0xA0):
        Array of (text_id: uint32, char_offset: uint32) pairs
        Sorted by text_id for binary search
        char_offset * 2 = byte offset from string section start
        char_offset = 0 means empty string

    String Section (starts after index):
        UTF-16LE null-terminated strings stored sequentially
        To find a string: use char_offset to locate position,
        then scan backwards for null (start) and forwards (end)
"""

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class LanguageExtractor:
    """Extracts text strings from WildStar language files."""

    MAGIC = b'XETL'
    HEADER_SIZE = 0xA0  # Index starts at offset 0xA0

    def __init__(self, filepath: str):
        self.filepath = filepath
        self._data: bytes = b''
        self._entry_count: int = 0
        self._string_section_start: int = 0
        self._text_ids: List[int] = []
        self._char_offsets: List[int] = []

    def extract(self) -> Dict[int, str]:
        """Extract all text entries from the language file."""
        with open(self.filepath, 'rb') as f:
            self._data = f.read()

        self._validate_header()
        self._read_index()
        return self._read_all_strings()

    def _validate_header(self):
        """Validate file header and extract metadata."""
        if len(self._data) < self.HEADER_SIZE:
            raise ValueError(f"File too small: {len(self._data)} bytes")

        magic = self._data[:4]
        if magic != self.MAGIC:
            raise ValueError(
                f"Invalid magic: {magic!r} (expected {self.MAGIC!r})"
            )

        # Entry count at offset 0x40
        self._entry_count = struct.unpack_from('<Q', self._data, 0x40)[0]

        # Calculate string section start (after index table)
        # Index entries are 8 bytes each (text_id: u32, char_offset: u32)
        self._string_section_start = self.HEADER_SIZE + (self._entry_count * 8)

        # Align to 16-byte boundary if needed
        if self._string_section_start % 16 != 0:
            self._string_section_start = (self._string_section_start + 15) & ~15

    def _read_index(self):
        """Read the text_id -> char_offset index table."""
        self._text_ids = []
        self._char_offsets = []

        for i in range(self._entry_count):
            offset = self.HEADER_SIZE + (i * 8)
            text_id, char_offset = struct.unpack_from('<II', self._data, offset)
            self._text_ids.append(text_id)
            self._char_offsets.append(char_offset)

    def _read_string_at_offset(self, char_offset: int) -> str:
        """Read a string given its character offset."""
        if char_offset == 0:
            return ''  # Empty string

        byte_offset = self._string_section_start + (char_offset * 2)
        if byte_offset >= len(self._data) - 1:
            return ''

        # Scan backwards to find string start (previous null terminator)
        start = byte_offset
        while start > self._string_section_start + 1:
            if self._data[start - 2] == 0 and self._data[start - 1] == 0:
                break
            start -= 2

        # Scan forwards to find string end (null terminator)
        end = byte_offset
        while end < len(self._data) - 1:
            if self._data[end] == 0 and self._data[end + 1] == 0:
                break
            end += 2

        try:
            return self._data[start:end].decode('utf-16-le')
        except UnicodeDecodeError:
            return ''

    def _read_all_strings(self) -> Dict[int, str]:
        """Read all strings from the file."""
        texts = {}
        for text_id, char_offset in zip(self._text_ids, self._char_offsets):
            texts[text_id] = self._read_string_at_offset(char_offset)
        return texts

    def get_info(self) -> dict:
        """Get metadata about the language file."""
        if not self._data:
            with open(self.filepath, 'rb') as f:
                self._data = f.read()
            self._validate_header()
            self._read_index()

        # Get locale info from header
        locale_id = struct.unpack_from('<I', self._data, 0x0C)[0]

        # Count non-empty strings
        non_empty = sum(1 for offset in self._char_offsets if offset != 0)

        return {
            'file': Path(self.filepath).name,
            'locale_id': locale_id,
            'entry_count': self._entry_count,
            'non_empty_strings': non_empty,
            'empty_strings': self._entry_count - non_empty,
            'string_section_start': hex(self._string_section_start),
            'file_size': len(self._data),
        }


def extract_language_file(
    input_path: str,
    output_path: Optional[str] = None,
    verbose: bool = False
) -> bool:
    """Extract a language file to JSON."""
    try:
        extractor = LanguageExtractor(input_path)

        if verbose:
            info = extractor.get_info()
            print(f"File: {info['file']}")
            print(f"  Locale ID: {info['locale_id']}")
            print(f"  Entries: {info['entry_count']}")
            print(f"  Non-empty: {info['non_empty_strings']}")
            print(f"  Empty: {info['empty_strings']}")

        texts = extractor.extract()

        if output_path is None:
            output_path = str(Path(input_path).with_suffix('.json'))

        # Convert int keys to strings for JSON serialization
        output_data = {"texts": {str(k): v for k, v in texts.items()}}

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(output_data, f, indent=2, ensure_ascii=False)

        print(f"Extracted {len(texts)} entries to {output_path}")
        return True

    except Exception as e:
        print(f"Error extracting {input_path}: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Extract WildStar language files to JSON',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s en-US.bin                    # Extract to en-US.json
  %(prog)s en-US.bin texts.json         # Extract to specific file
  %(prog)s --info en-US.bin             # Show file info only
        """
    )

    parser.add_argument('input', help='Input language file (.bin)')
    parser.add_argument('output', nargs='?', help='Output JSON file')
    parser.add_argument('--info', action='store_true',
                        help='Show file info without extracting')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Verbose output')

    args = parser.parse_args()

    if args.info:
        try:
            extractor = LanguageExtractor(args.input)
            info = extractor.get_info()
            print(f"File: {info['file']}")
            print(f"Locale ID: {info['locale_id']}")
            print(f"Entry count: {info['entry_count']}")
            print(f"Non-empty strings: {info['non_empty_strings']}")
            print(f"Empty strings: {info['empty_strings']}")
            print(f"String section: {info['string_section_start']}")
            print(f"File size: {info['file_size']:,} bytes")
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        if not extract_language_file(args.input, args.output, args.verbose):
            sys.exit(1)


if __name__ == '__main__':
    main()
