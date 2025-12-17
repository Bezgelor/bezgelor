"""Tests for glTF exporter."""
import io
import os
import struct
import tempfile
import pytest
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gltf_exporter import GLTFExporter


def create_test_m3_with_mesh(vertices, indices):
    """Create a synthetic M3 file with mesh data."""
    vertex_data = b""
    for x, y, z in vertices:
        vertex_data += struct.pack("<fff", x, y, z)

    index_data = b""
    for idx in indices:
        index_data += struct.pack("<H", idx)

    header = b"LDOM"
    header += struct.pack("<I", 1)
    header += struct.pack("<I", 16)
    header += struct.pack("<I", 2)

    vpos_offset = 48
    indx_offset = vpos_offset + len(vertex_data)

    vpos_chunk = b"VPOS"
    vpos_chunk += struct.pack("<I", vpos_offset)
    vpos_chunk += struct.pack("<I", len(vertex_data))
    vpos_chunk += struct.pack("<I", 0)

    indx_chunk = b"INDX"
    indx_chunk += struct.pack("<I", indx_offset)
    indx_chunk += struct.pack("<I", len(index_data))
    indx_chunk += struct.pack("<I", 0)

    data = header + vpos_chunk + indx_chunk + vertex_data + index_data
    return io.BytesIO(data)


def test_export_basic_mesh():
    """Should export M3 to valid glTF file."""
    vertices = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    indices = [0, 1, 2]

    m3_file = create_test_m3_with_mesh(vertices, indices)

    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = os.path.join(tmpdir, "test.glb")

        exporter = GLTFExporter(m3_file)
        exporter.export(output_path)

        assert os.path.exists(output_path)
        assert os.path.getsize(output_path) > 100

        # Verify it's valid glTF
        from pygltflib import GLTF2
        gltf = GLTF2.load(output_path)
        assert len(gltf.meshes) > 0


def test_export_quad():
    """Should export a quad (2 triangles) correctly."""
    vertices = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    indices = [0, 1, 2, 0, 2, 3]

    m3_file = create_test_m3_with_mesh(vertices, indices)

    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = os.path.join(tmpdir, "quad.glb")

        exporter = GLTFExporter(m3_file)
        exporter.export(output_path)

        from pygltflib import GLTF2
        gltf = GLTF2.load(output_path)

        # Should have 4 vertices
        pos_accessor = gltf.accessors[0]
        assert pos_accessor.count == 4


def test_export_no_mesh_raises():
    """Should raise when no mesh data found."""
    header = b"LDOM"
    header += struct.pack("<I", 1)
    header += struct.pack("<I", 16)
    header += struct.pack("<I", 0)

    m3_file = io.BytesIO(header)

    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = os.path.join(tmpdir, "empty.glb")

        exporter = GLTFExporter(m3_file)
        with pytest.raises(ValueError, match="No mesh data"):
            exporter.export(output_path)


def create_test_m3_with_mesh_and_bones(vertices, indices, bones):
    """Create a synthetic M3 file with mesh and skeleton data.

    Args:
        vertices: List of (x, y, z) tuples
        indices: List of triangle indices
        bones: List of dicts with 'id', 'parent_id', 'transform' (16 floats)
    """
    vertex_data = b""
    for x, y, z in vertices:
        vertex_data += struct.pack("<fff", x, y, z)

    index_data = b""
    for idx in indices:
        index_data += struct.pack("<H", idx)

    # Bone data: id(4) + parent_id(4) + transform(64) = 72 bytes each
    bone_data = b""
    for bone in bones:
        bone_data += struct.pack("<I", bone["id"])
        bone_data += struct.pack("<i", bone["parent_id"])
        transform = bone.get(
            "transform", [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        )
        bone_data += struct.pack("<16f", *transform)

    header = b"LDOM"
    header += struct.pack("<I", 1)
    header += struct.pack("<I", 16)
    header += struct.pack("<I", 3)  # 3 chunks: VPOS, INDX, BONE

    vpos_offset = 64  # header(16) + 3 chunk headers(16*3) = 64
    indx_offset = vpos_offset + len(vertex_data)
    bone_offset = indx_offset + len(index_data)

    vpos_chunk = b"VPOS"
    vpos_chunk += struct.pack("<I", vpos_offset)
    vpos_chunk += struct.pack("<I", len(vertex_data))
    vpos_chunk += struct.pack("<I", 0)

    indx_chunk = b"INDX"
    indx_chunk += struct.pack("<I", indx_offset)
    indx_chunk += struct.pack("<I", len(index_data))
    indx_chunk += struct.pack("<I", 0)

    bone_chunk = b"BONE"
    bone_chunk += struct.pack("<I", bone_offset)
    bone_chunk += struct.pack("<I", len(bone_data))
    bone_chunk += struct.pack("<I", len(bones))

    data = header + vpos_chunk + indx_chunk + bone_chunk + vertex_data + index_data + bone_data
    return io.BytesIO(data)


def test_export_with_skeleton():
    """Should export M3 with skeleton to glTF."""
    vertices = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    indices = [0, 1, 2]
    bones = [
        {"id": 0, "parent_id": -1},  # Root bone
        {"id": 1, "parent_id": 0},   # Child bone
    ]

    m3_file = create_test_m3_with_mesh_and_bones(vertices, indices, bones)

    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = os.path.join(tmpdir, "character.glb")

        exporter = GLTFExporter(m3_file)
        exporter.export(output_path, include_skeleton=True)

        from pygltflib import GLTF2
        gltf = GLTF2.load(output_path)

        # Should have skin with joints
        assert gltf.skins is not None and len(gltf.skins) > 0
        assert len(gltf.skins[0].joints) == 2


def test_export_skeleton_hierarchy():
    """Skeleton should preserve parent-child relationships."""
    vertices = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    indices = [0, 1, 2]
    bones = [
        {"id": 0, "parent_id": -1},  # Root
        {"id": 1, "parent_id": 0},   # Child of root
        {"id": 2, "parent_id": 1},   # Grandchild
    ]

    m3_file = create_test_m3_with_mesh_and_bones(vertices, indices, bones)

    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = os.path.join(tmpdir, "hierarchy.glb")

        exporter = GLTFExporter(m3_file)
        exporter.export(output_path, include_skeleton=True)

        from pygltflib import GLTF2
        gltf = GLTF2.load(output_path)

        # Verify 3 joint nodes exist
        assert len(gltf.skins[0].joints) == 3

        # Verify hierarchy - child nodes should have parent references
        # Joint indices point to nodes in the node list
        joint_indices = gltf.skins[0].joints

        # Root node should have no parent (checked via children)
        root_node_idx = joint_indices[0]
        root_node = gltf.nodes[root_node_idx]
        assert root_node.children is not None and len(root_node.children) > 0


def create_test_m3_with_animations(vertices, indices, bones, animations):
    """Create a synthetic M3 file with mesh, skeleton, and animation data.

    Args:
        vertices: List of (x, y, z) tuples
        indices: List of triangle indices
        bones: List of dicts with 'id', 'parent_id', 'transform'
        animations: List of dicts with 'id', 'duration', 'keyframes'
            keyframes: List of dicts with 'time', 'bone_id', 'position', 'rotation'
    """
    vertex_data = b""
    for x, y, z in vertices:
        vertex_data += struct.pack("<fff", x, y, z)

    index_data = b""
    for idx in indices:
        index_data += struct.pack("<H", idx)

    # Bone data: id(4) + parent_id(4) + transform(64) = 72 bytes each
    bone_data = b""
    for bone in bones:
        bone_data += struct.pack("<I", bone["id"])
        bone_data += struct.pack("<i", bone["parent_id"])
        transform = bone.get(
            "transform", [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        )
        bone_data += struct.pack("<16f", *transform)

    # Animation headers: id(4) + duration(4) + keyframe_count(4) + keyframe_offset(4) = 16 bytes each
    # Keyframes: time(4) + bone_id(4) + position(12) + rotation(16) = 36 bytes each
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
            rot = kf.get("rotation", (0, 0, 0, 1))
            keyframe_data += struct.pack("<4f", *rot)
            keyframe_offset += 36

    # Calculate chunk offsets
    # header(16) + 5 chunk headers(16*5) = 96
    chunk_count = 5  # VPOS, INDX, BONE, ANIM, KEYF
    data_start = 16 + (chunk_count * 16)

    vpos_offset = data_start
    indx_offset = vpos_offset + len(vertex_data)
    bone_offset = indx_offset + len(index_data)
    anim_offset = bone_offset + len(bone_data)
    keyf_offset = anim_offset + len(anim_headers)

    header = b"LDOM"
    header += struct.pack("<I", 1)
    header += struct.pack("<I", 16)
    header += struct.pack("<I", chunk_count)

    vpos_chunk = b"VPOS"
    vpos_chunk += struct.pack("<I", vpos_offset)
    vpos_chunk += struct.pack("<I", len(vertex_data))
    vpos_chunk += struct.pack("<I", 0)

    indx_chunk = b"INDX"
    indx_chunk += struct.pack("<I", indx_offset)
    indx_chunk += struct.pack("<I", len(index_data))
    indx_chunk += struct.pack("<I", 0)

    bone_chunk = b"BONE"
    bone_chunk += struct.pack("<I", bone_offset)
    bone_chunk += struct.pack("<I", len(bone_data))
    bone_chunk += struct.pack("<I", len(bones))

    anim_chunk = b"ANIM"
    anim_chunk += struct.pack("<I", anim_offset)
    anim_chunk += struct.pack("<I", len(anim_headers))
    anim_chunk += struct.pack("<I", len(animations))

    keyf_chunk = b"KEYF"
    keyf_chunk += struct.pack("<I", keyf_offset)
    keyf_chunk += struct.pack("<I", len(keyframe_data))
    keyf_chunk += struct.pack("<I", 0)

    data = (
        header
        + vpos_chunk
        + indx_chunk
        + bone_chunk
        + anim_chunk
        + keyf_chunk
        + vertex_data
        + index_data
        + bone_data
        + anim_headers
        + keyframe_data
    )
    return io.BytesIO(data)


def test_export_with_animations():
    """Should export M3 with animations to glTF."""
    vertices = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    indices = [0, 1, 2]
    bones = [
        {"id": 0, "parent_id": -1},
    ]
    animations = [
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

    m3_file = create_test_m3_with_animations(vertices, indices, bones, animations)

    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = os.path.join(tmpdir, "animated.glb")

        exporter = GLTFExporter(m3_file)
        exporter.export(output_path, include_skeleton=True, include_animations=True)

        from pygltflib import GLTF2
        gltf = GLTF2.load(output_path)

        # Should have animations
        assert gltf.animations is not None and len(gltf.animations) > 0


def test_export_animation_channels():
    """Animation should have translation and rotation channels."""
    vertices = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    indices = [0, 1, 2]
    bones = [
        {"id": 0, "parent_id": -1},
        {"id": 1, "parent_id": 0},
    ]
    animations = [
        {
            "id": 0,
            "duration": 1.0,
            "keyframes": [
                {"time": 0.0, "bone_id": 0, "position": (0, 0, 0), "rotation": (0, 0, 0, 1)},
                {"time": 1.0, "bone_id": 0, "position": (0, 1, 0), "rotation": (0, 0, 0, 1)},
                {"time": 0.0, "bone_id": 1, "position": (1, 0, 0), "rotation": (0, 0, 0, 1)},
                {"time": 1.0, "bone_id": 1, "position": (1, 1, 0), "rotation": (0, 0, 0, 1)},
            ],
        }
    ]

    m3_file = create_test_m3_with_animations(vertices, indices, bones, animations)

    with tempfile.TemporaryDirectory() as tmpdir:
        output_path = os.path.join(tmpdir, "channels.glb")

        exporter = GLTFExporter(m3_file)
        exporter.export(output_path, include_skeleton=True, include_animations=True)

        from pygltflib import GLTF2
        gltf = GLTF2.load(output_path)

        anim = gltf.animations[0]
        # Should have channels for translation and rotation
        assert len(anim.channels) >= 2  # At least 2 bones x (translation or rotation)
