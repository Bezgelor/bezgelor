"""Tests for M3 skeleton/bone extraction."""
import io
import struct
import pytest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from m3_skeleton import M3SkeletonExtractor


def create_test_m3_with_bones(bones):
    """Create a synthetic M3 file with bone data.

    Args:
        bones: List of dicts with 'id', 'parent_id', 'transform' (16 floats)

    Returns:
        BytesIO with M3 data
    """
    # Each bone: id(4) + parent_id(4) + transform(64) = 72 bytes
    bone_data = b""
    for bone in bones:
        bone_data += struct.pack("<I", bone["id"])
        bone_data += struct.pack("<i", bone["parent_id"])  # signed for -1
        # 4x4 transform matrix as 16 floats
        transform = bone.get("transform", [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
        bone_data += struct.pack("<16f", *transform)

    header = b"LDOM"
    header += struct.pack("<I", 1)  # version
    header += struct.pack("<I", 16)  # index_offset
    header += struct.pack("<I", 1)  # index_count (1 chunk: BONE)

    # BONE chunk header
    bone_chunk = b"BONE"
    bone_chunk += struct.pack("<I", 32)  # offset
    bone_chunk += struct.pack("<I", len(bone_data))  # size
    bone_chunk += struct.pack("<I", 0)  # property_a

    data = header + bone_chunk + bone_data
    return io.BytesIO(data)


def test_extract_bones_basic():
    """Should extract bone hierarchy from BONE chunk."""
    test_bones = [
        {"id": 0, "parent_id": -1},  # Root bone
        {"id": 1, "parent_id": 0},  # Child of root
        {"id": 2, "parent_id": 0},  # Another child of root
        {"id": 3, "parent_id": 1},  # Grandchild
    ]
    file = create_test_m3_with_bones(test_bones)

    extractor = M3SkeletonExtractor(file)
    bones = extractor.get_bones()

    assert len(bones) == 4
    for bone in bones:
        assert "id" in bone
        assert "parent_id" in bone
        assert "transform" in bone


def test_extract_bones_hierarchy():
    """Bones should have correct parent relationships."""
    test_bones = [
        {"id": 0, "parent_id": -1},
        {"id": 1, "parent_id": 0},
    ]
    file = create_test_m3_with_bones(test_bones)

    extractor = M3SkeletonExtractor(file)
    bones = extractor.get_bones()

    assert bones[0]["parent_id"] == -1  # Root has no parent
    assert bones[1]["parent_id"] == 0  # Child references root


def test_extract_bones_transform():
    """Bones should have transform matrices."""
    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    test_bones = [{"id": 0, "parent_id": -1, "transform": identity}]
    file = create_test_m3_with_bones(test_bones)

    extractor = M3SkeletonExtractor(file)
    bones = extractor.get_bones()

    assert len(bones[0]["transform"]) == 16
    # Check identity matrix values
    assert abs(bones[0]["transform"][0] - 1.0) < 0.001
    assert abs(bones[0]["transform"][5] - 1.0) < 0.001


def test_extract_bones_empty():
    """Should return empty list when no BONE chunk."""
    header = b"LDOM"
    header += struct.pack("<I", 1)
    header += struct.pack("<I", 16)
    header += struct.pack("<I", 0)

    file = io.BytesIO(header)
    extractor = M3SkeletonExtractor(file)

    assert extractor.get_bones() == []
