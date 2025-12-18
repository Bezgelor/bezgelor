"""Tests for M3 file parser."""
import pytest
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from m3_parser import M3Parser


def test_parse_header_invalid_magic():
    """Should raise on invalid magic bytes."""
    parser = M3Parser()
    with pytest.raises(ValueError, match="Invalid M3 magic"):
        parser.parse_header_bytes(b"XXXX" + b"\x00" * 100)


def test_parse_header_ldom_magic():
    """Should accept LDOM magic bytes."""
    parser = M3Parser()
    # LDOM magic + version(1) + padding
    data = b"LDOM" + b"\x01\x00\x00\x00" + b"\x00" * 100
    header = parser.parse_header_bytes(data)

    assert header.magic == b"LDOM"
    assert header.version == 1


def test_parse_header_43md_magic():
    """Should accept 43MD magic bytes."""
    parser = M3Parser()
    # 43MD magic + version(2) + padding
    data = b"43MD" + b"\x02\x00\x00\x00" + b"\x00" * 100
    header = parser.parse_header_bytes(data)

    assert header.magic == b"43MD"
    assert header.version == 2


def test_parse_chunks_from_bytes():
    """Should parse chunk index from byte data."""
    import io
    from m3_types import M3Chunk

    parser = M3Parser()

    # Build a fake M3 file with:
    # - Header (16 bytes): magic + version + index_offset(16) + index_count(2)
    # - Chunk index at offset 16: 2 chunks, each 16 bytes
    header = b"LDOM"  # magic
    header += b"\x01\x00\x00\x00"  # version = 1
    header += b"\x10\x00\x00\x00"  # index_offset = 16
    header += b"\x02\x00\x00\x00"  # index_count = 2

    # Chunk 1: MES3 at offset 48, size 100
    chunk1 = b"MES3"  # id
    chunk1 += b"\x30\x00\x00\x00"  # offset = 48
    chunk1 += b"\x64\x00\x00\x00"  # size = 100
    chunk1 += b"\x00\x00\x00\x00"  # property_a = 0

    # Chunk 2: VPOS at offset 148, size 200
    chunk2 = b"VPOS"  # id
    chunk2 += b"\x94\x00\x00\x00"  # offset = 148
    chunk2 += b"\xc8\x00\x00\x00"  # size = 200
    chunk2 += b"\x00\x00\x00\x00"  # property_a = 0

    data = header + chunk1 + chunk2
    file = io.BytesIO(data)

    chunks = parser.parse_chunks(file)

    assert len(chunks) == 2
    assert all(isinstance(c, M3Chunk) for c in chunks)

    assert chunks[0].id == "MES3"
    assert chunks[0].offset == 48
    assert chunks[0].size == 100

    assert chunks[1].id == "VPOS"
    assert chunks[1].offset == 148
    assert chunks[1].size == 200


def test_parse_chunks_empty():
    """Should return empty list when index_count is 0."""
    import io

    parser = M3Parser()

    # Header with index_count = 0
    header = b"LDOM"
    header += b"\x01\x00\x00\x00"  # version
    header += b"\x10\x00\x00\x00"  # index_offset = 16
    header += b"\x00\x00\x00\x00"  # index_count = 0

    file = io.BytesIO(header)
    chunks = parser.parse_chunks(file)

    assert chunks == []
