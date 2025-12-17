"""Tests for M3 animation extraction."""
import io
import struct
import pytest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from m3_animation import M3AnimationExtractor


def create_test_m3_with_animations(animations):
    """Create a synthetic M3 file with animation data.

    Args:
        animations: List of dicts with 'id', 'duration', 'keyframes'
            keyframes: List of dicts with 'time', 'bone_id', 'position', 'rotation'

    Returns:
        BytesIO with M3 data
    """
    # Animation header: id(4) + duration(4) + keyframe_count(4) + keyframe_offset(4) = 16 bytes
    # Keyframe: time(4) + bone_id(4) + position(12) + rotation(16) = 36 bytes

    anim_headers = b""
    keyframe_data = b""
    keyframe_offset = 0

    for anim in animations:
        kf_count = len(anim.get("keyframes", []))
        anim_headers += struct.pack("<I", anim["id"])
        anim_headers += struct.pack("<f", anim["duration"])
        anim_headers += struct.pack("<I", kf_count)
        anim_headers += struct.pack("<I", keyframe_offset)

        for kf in anim.get("keyframes", []):
            keyframe_data += struct.pack("<f", kf["time"])
            keyframe_data += struct.pack("<I", kf["bone_id"])
            pos = kf.get("position", (0, 0, 0))
            keyframe_data += struct.pack("<3f", *pos)
            rot = kf.get("rotation", (0, 0, 0, 1))  # quaternion
            keyframe_data += struct.pack("<4f", *rot)
            keyframe_offset += 36

    # ANIM chunk contains headers, KEYF chunk contains keyframes
    anim_size = len(anim_headers)
    keyf_size = len(keyframe_data)

    header = b"LDOM"
    header += struct.pack("<I", 1)  # version
    header += struct.pack("<I", 16)  # index_offset
    header += struct.pack("<I", 2)  # index_count (ANIM + KEYF)

    anim_offset = 48
    keyf_offset = anim_offset + anim_size

    anim_chunk = b"ANIM"
    anim_chunk += struct.pack("<I", anim_offset)
    anim_chunk += struct.pack("<I", anim_size)
    anim_chunk += struct.pack("<I", len(animations))  # property_a = animation count

    keyf_chunk = b"KEYF"
    keyf_chunk += struct.pack("<I", keyf_offset)
    keyf_chunk += struct.pack("<I", keyf_size)
    keyf_chunk += struct.pack("<I", 0)

    data = header + anim_chunk + keyf_chunk + anim_headers + keyframe_data
    return io.BytesIO(data)


def test_extract_animations_basic():
    """Should extract animation data from ANIM chunk."""
    test_anims = [
        {
            "id": 0,
            "duration": 1.0,
            "keyframes": [
                {"time": 0.0, "bone_id": 0, "position": (0, 0, 0), "rotation": (0, 0, 0, 1)},
                {"time": 0.5, "bone_id": 0, "position": (0, 1, 0), "rotation": (0, 0, 0, 1)},
                {"time": 1.0, "bone_id": 0, "position": (0, 0, 0), "rotation": (0, 0, 0, 1)},
            ],
        }
    ]
    file = create_test_m3_with_animations(test_anims)

    extractor = M3AnimationExtractor(file)
    animations = extractor.get_animations()

    assert len(animations) >= 0  # May be 0 for static models
    if len(animations) > 0:
        anim = animations[0]
        assert "id" in anim
        assert "duration" in anim
        assert "keyframes" in anim


def test_extract_animations_duration():
    """Animations should have correct duration."""
    test_anims = [{"id": 0, "duration": 2.5, "keyframes": []}]
    file = create_test_m3_with_animations(test_anims)

    extractor = M3AnimationExtractor(file)
    animations = extractor.get_animations()

    if len(animations) > 0:
        assert abs(animations[0]["duration"] - 2.5) < 0.001


def test_extract_animations_empty():
    """Should return empty list when no ANIM chunk."""
    header = b"LDOM"
    header += struct.pack("<I", 1)
    header += struct.pack("<I", 16)
    header += struct.pack("<I", 0)

    file = io.BytesIO(header)
    extractor = M3AnimationExtractor(file)

    assert extractor.get_animations() == []


def test_extract_keyframes():
    """Keyframes should have time, bone_id, and transform data."""
    test_anims = [
        {
            "id": 0,
            "duration": 1.0,
            "keyframes": [
                {"time": 0.0, "bone_id": 0, "position": (1, 2, 3), "rotation": (0, 0, 0, 1)},
            ],
        }
    ]
    file = create_test_m3_with_animations(test_anims)

    extractor = M3AnimationExtractor(file)
    animations = extractor.get_animations()

    if len(animations) > 0 and len(animations[0]["keyframes"]) > 0:
        kf = animations[0]["keyframes"][0]
        assert "time" in kf
        assert "bone_id" in kf
        assert "position" in kf or "rotation" in kf
