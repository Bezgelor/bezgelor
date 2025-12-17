"""Type definitions for M3 model format."""
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class M3Header:
    """M3 file header."""

    magic: bytes
    version: int
    index_offset: int = 0
    index_count: int = 0


@dataclass
class M3Chunk:
    """M3 file chunk."""

    id: str
    offset: int
    size: int
    property_a: int = 0
    property_b: int = 0
    data: Optional[bytes] = None
