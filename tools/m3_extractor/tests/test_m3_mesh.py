"""Tests for M3 mesh extraction."""
import io
import struct
import pytest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from m3_mesh import M3MeshExtractor


def create_test_m3_with_vertices(vertices):
    """Create a synthetic M3 file with vertex data.

    Args:
        vertices: List of (x, y, z) tuples

    Returns:
        BytesIO with M3 data
    """
    # Header: magic + version + index_offset + index_count
    # Chunk index starts at offset 16
    # VPOS chunk data starts at offset 48
    vertex_data = b""
    for x, y, z in vertices:
        vertex_data += struct.pack("<fff", x, y, z)

    header = b"LDOM"
    header += struct.pack("<I", 1)  # version
    header += struct.pack("<I", 16)  # index_offset
    header += struct.pack("<I", 1)  # index_count (1 chunk: VPOS)

    # VPOS chunk header at offset 16
    vpos_chunk = b"VPOS"
    vpos_chunk += struct.pack("<I", 32)  # data offset (right after chunk index)
    vpos_chunk += struct.pack("<I", len(vertex_data))  # size
    vpos_chunk += struct.pack("<I", 0)  # property_a

    # Assemble file
    data = header + vpos_chunk + vertex_data
    return io.BytesIO(data)


def test_extract_vertices_basic():
    """Should extract vertex positions from VPOS chunk."""
    test_vertices = [
        (1.0, 2.0, 3.0),
        (4.0, 5.0, 6.0),
        (7.0, 8.0, 9.0),
    ]
    file = create_test_m3_with_vertices(test_vertices)

    extractor = M3MeshExtractor(file)
    vertices = extractor.get_vertices()

    assert len(vertices) == 3
    assert all(len(v) == 3 for v in vertices)

    # Check values (with float tolerance)
    for i, (expected, actual) in enumerate(zip(test_vertices, vertices)):
        assert abs(actual[0] - expected[0]) < 0.001
        assert abs(actual[1] - expected[1]) < 0.001
        assert abs(actual[2] - expected[2]) < 0.001


def test_extract_vertices_empty():
    """Should return empty list when no VPOS chunk."""
    # M3 file with no chunks
    header = b"LDOM"
    header += struct.pack("<I", 1)  # version
    header += struct.pack("<I", 16)  # index_offset
    header += struct.pack("<I", 0)  # index_count = 0

    file = io.BytesIO(header)
    extractor = M3MeshExtractor(file)
    vertices = extractor.get_vertices()

    assert vertices == []


def test_extract_vertices_reasonable_range():
    """Vertices should be within reasonable coordinate range."""
    test_vertices = [
        (100.5, -50.25, 0.0),
        (-1000.0, 500.0, 250.0),
    ]
    file = create_test_m3_with_vertices(test_vertices)

    extractor = M3MeshExtractor(file)
    vertices = extractor.get_vertices()

    for v in vertices:
        assert all(-10000 < coord < 10000 for coord in v)
