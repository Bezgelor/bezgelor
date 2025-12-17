"""Mesh extraction from WildStar M3 model files.

WildStar M3 format (based on akderebur's gist):
- Magic: LDOM (little-endian "MODL") = 1297040460
- Mesh table offset at byte 600 (int64)
- Header ends at byte 1584
- Mesh table structure:
  - +24: vertCount (int32)
  - +28: blockLen (int16) - vertex stride
  - +104: indCount (int32) - but we use per-submesh counts
  - +120: indOff (int64) - index offset from vbStart
  - +128: smCount (int64) - submesh count
  - +136: smTOff (int64) - submesh table offset from vbStart
- Vertex buffer starts at mesh_table + 208
- Vertices: 3x int16 normalized positions (divide by 32767)
- UVs: 2x half-precision floats (last 4 bytes of block)
- Submesh table entries are 112 bytes each
"""
import struct
from dataclasses import dataclass, field
from typing import BinaryIO, List, Tuple, Union
from pathlib import Path


@dataclass
class Submesh:
    """Represents a submesh within the M3 file."""
    vertices: List[Tuple[float, float, float]] = field(default_factory=list)
    uvs: List[Tuple[float, float]] = field(default_factory=list)
    indices: List[int] = field(default_factory=list)
    start_vertex: int = 0
    start_index: int = 0


def half_to_float(data: bytes) -> float:
    """Convert IEEE 754 half-precision float bytes to Python float.

    Args:
        data: 2 bytes of half-precision float

    Returns:
        Python float
    """
    h = struct.unpack("<H", data)[0]
    s = (h >> 15) & 0x1
    e = (h >> 10) & 0x1f
    m = h & 0x3ff

    if e == 0:
        if m == 0:
            return -0.0 if s else 0.0
        # Denormalized
        return ((-1) ** s) * (m / 1024.0) * (2 ** -14)
    elif e == 31:
        if m == 0:
            return float('-inf') if s else float('inf')
        return float('nan')
    else:
        return ((-1) ** s) * (2 ** (e - 15)) * (1 + m / 1024.0)


class M3MeshExtractor:
    """Extracts mesh data from WildStar M3 files."""

    MAGIC_LDOM = 1297040460  # "LDOM" as int32 little-endian
    HEADER_SIZE = 1584
    MESH_TABLE_OFFSET_POS = 600
    SUBMESH_ENTRY_SIZE = 112

    def __init__(self, source: Union[str, Path, BinaryIO]):
        """Initialize extractor with file path or file-like object.

        Args:
            source: Path to M3 file or file-like object
        """
        self.source = source
        self._submeshes: List[Submesh] = None
        self._all_vertices: List[Tuple[float, float, float]] = []
        self._all_uvs: List[Tuple[float, float]] = []
        self._all_indices: List[int] = []
        self._parsed = False

    def _get_file(self) -> BinaryIO:
        """Get file handle, opening if needed."""
        if isinstance(self.source, (str, Path)):
            return open(self.source, "rb")
        self.source.seek(0)
        return self.source

    def _close_file(self, file: BinaryIO):
        """Close file if we opened it."""
        if isinstance(self.source, (str, Path)):
            file.close()

    def _parse(self):
        """Parse M3 file and extract all mesh data."""
        if self._parsed:
            return

        file = self._get_file()
        try:
            # Check magic
            magic = struct.unpack("<i", file.read(4))[0]
            if magic != self.MAGIC_LDOM:
                self._submeshes = []
                self._parsed = True
                return

            # Get mesh table offset
            file.seek(self.MESH_TABLE_OFFSET_POS)
            mesh_table_offset = struct.unpack("<q", file.read(8))[0]

            # Seek to mesh table
            mesh_table_pos = self.HEADER_SIZE + mesh_table_offset
            file.seek(mesh_table_pos)

            # Read mesh table header (256 bytes to be safe)
            header = file.read(256)

            # Parse using correct offsets from the gist
            vert_count = struct.unpack("<I", header[24:28])[0]
            block_len = struct.unpack("<H", header[28:30])[0]

            # Skip to +120 for indOff, +128 for smCount, +136 for smTOff
            ind_off = struct.unpack("<q", header[120:128])[0]
            sm_count = struct.unpack("<q", header[128:136])[0]
            sm_t_off = struct.unpack("<q", header[136:144])[0]

            # Vertex buffer starts at mesh_table + 208 (144 + 64)
            vb_start = mesh_table_pos + 208

            # Calculate offsets
            ind_start = vb_start + ind_off
            sm_start = vb_start + sm_t_off

            # Validate offsets
            file.seek(0, 2)
            file_size = file.tell()

            if sm_start >= file_size or ind_start >= file_size or sm_count <= 0:
                self._submeshes = []
                self._parsed = True
                return

            # Read submeshes
            submeshes = []
            all_vertices = []
            all_uvs = []
            all_indices = []
            vertex_offset = 0

            for s in range(sm_count):
                file.seek(sm_start + self.SUBMESH_ENTRY_SIZE * s)

                start_index = struct.unpack("<i", file.read(4))[0]
                start_vertex = struct.unpack("<i", file.read(4))[0]
                s_ind_count = struct.unpack("<i", file.read(4))[0]
                s_vert_count = struct.unpack("<i", file.read(4))[0]

                # Read vertices for this submesh
                vertices = []
                uvs = []

                file.seek(vb_start + block_len * start_vertex)

                for v in range(s_vert_count):
                    # Read position: 3x int16
                    x = struct.unpack("<h", file.read(2))[0] / 32767.0
                    y = struct.unpack("<h", file.read(2))[0] / 32767.0
                    z = struct.unpack("<h", file.read(2))[0] / 32767.0
                    vertices.append((x, y, z))

                    # Skip to UV (last 4 bytes of block)
                    # We've read 6 bytes, need to skip (block_len - 10) to get to UV
                    if block_len > 10:
                        file.seek(block_len - 10, 1)

                    # Read UV: 2x half float
                    u = half_to_float(file.read(2))
                    v_coord = half_to_float(file.read(2))
                    uvs.append((u, v_coord))

                # Read indices for this submesh
                indices = []
                file.seek(ind_start + 2 * start_index)

                for i in range(s_ind_count):
                    idx = struct.unpack("<H", file.read(2))[0]
                    indices.append(idx)

                submesh = Submesh(
                    vertices=vertices,
                    uvs=uvs,
                    indices=indices,
                    start_vertex=start_vertex,
                    start_index=start_index
                )
                submeshes.append(submesh)

                # Add to combined lists with offset adjustment
                all_vertices.extend(vertices)
                all_uvs.extend(uvs)
                # Adjust indices for combined mesh (indices are relative to submesh)
                all_indices.extend(idx + vertex_offset for idx in indices)
                vertex_offset += len(vertices)

            self._submeshes = submeshes
            self._all_vertices = all_vertices
            self._all_uvs = all_uvs
            self._all_indices = all_indices
            self._parsed = True

        except Exception as e:
            print(f"Parse error: {e}")
            import traceback
            traceback.print_exc()
            self._submeshes = []
            self._parsed = True

        finally:
            self._close_file(file)

    def get_vertices(self) -> List[Tuple[float, float, float]]:
        """Extract vertex positions.

        Returns:
            List of (x, y, z) tuples normalized to -1..1 range
        """
        self._parse()
        return self._all_vertices

    def get_uvs(self) -> List[Tuple[float, float]]:
        """Extract UV texture coordinates.

        Returns:
            List of (u, v) tuples
        """
        self._parse()
        return self._all_uvs

    def get_indices(self) -> List[int]:
        """Extract triangle indices.

        Returns:
            List of vertex indices (every 3 form a triangle)
        """
        self._parse()
        return self._all_indices

    def get_submeshes(self) -> List[Submesh]:
        """Get all submeshes.

        Returns:
            List of Submesh objects
        """
        self._parse()
        return self._submeshes
