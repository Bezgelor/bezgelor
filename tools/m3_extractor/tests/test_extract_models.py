"""Tests for M3 extraction CLI."""
import io
import os
import struct
import subprocess
import sys
import tempfile
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def create_test_m3_file(vertices, indices):
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

    return header + vpos_chunk + indx_chunk + vertex_data + index_data


def test_cli_help():
    """CLI should show help."""
    result = subprocess.run(
        [sys.executable, "extract_models.py", "--help"],
        capture_output=True,
        text=True,
        cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    )
    assert result.returncode == 0
    assert "usage" in result.stdout.lower()


def test_cli_extract_single():
    """CLI should extract a single M3 file."""
    vertices = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    indices = [0, 1, 2]
    m3_data = create_test_m3_file(vertices, indices)

    with tempfile.TemporaryDirectory() as tmpdir:
        # Create test M3 file
        input_path = os.path.join(tmpdir, "test.m3")
        with open(input_path, "wb") as f:
            f.write(m3_data)

        output_dir = os.path.join(tmpdir, "output")

        result = subprocess.run(
            [sys.executable, "extract_models.py", input_path, "-o", output_dir],
            capture_output=True,
            text=True,
            cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        )

        assert result.returncode == 0
        assert os.path.exists(os.path.join(output_dir, "test.glb"))


def test_cli_extract_directory():
    """CLI should extract all M3 files from a directory."""
    vertices = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    indices = [0, 1, 2]
    m3_data = create_test_m3_file(vertices, indices)

    with tempfile.TemporaryDirectory() as tmpdir:
        # Create test M3 files
        input_dir = os.path.join(tmpdir, "models")
        os.makedirs(input_dir)

        for name in ["model1.m3", "model2.m3"]:
            with open(os.path.join(input_dir, name), "wb") as f:
                f.write(m3_data)

        output_dir = os.path.join(tmpdir, "output")

        result = subprocess.run(
            [sys.executable, "extract_models.py", input_dir, "-o", output_dir],
            capture_output=True,
            text=True,
            cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        )

        assert result.returncode == 0
        assert os.path.exists(os.path.join(output_dir, "model1.glb"))
        assert os.path.exists(os.path.join(output_dir, "model2.glb"))


def test_cli_no_skeleton_flag():
    """CLI should respect --no-skeleton flag."""
    vertices = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    ]
    indices = [0, 1, 2]
    m3_data = create_test_m3_file(vertices, indices)

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "test.m3")
        with open(input_path, "wb") as f:
            f.write(m3_data)

        output_dir = os.path.join(tmpdir, "output")

        result = subprocess.run(
            [sys.executable, "extract_models.py", input_path, "-o", output_dir, "--no-skeleton"],
            capture_output=True,
            text=True,
            cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        )

        assert result.returncode == 0
        assert os.path.exists(os.path.join(output_dir, "test.glb"))
