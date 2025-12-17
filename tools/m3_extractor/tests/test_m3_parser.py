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
