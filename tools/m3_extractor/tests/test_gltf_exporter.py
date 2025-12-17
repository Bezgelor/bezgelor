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
