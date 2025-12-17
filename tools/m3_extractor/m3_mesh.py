"""Mesh extraction from M3 model files."""
import struct
from typing import BinaryIO, List, Tuple, Union
from pathlib import Path

from m3_parser import M3Parser
from m3_types import M3Chunk


class M3MeshExtractor:
    """Extracts mesh data (vertices, indices) from M3 files."""

    def __init__(self, source: Union[str, Path, BinaryIO]):
        """Initialize extractor with file path or file-like object.

        Args:
            source: Path to M3 file or file-like object
        """
        self.source = source
        self.parser = M3Parser()
        self._chunks: List[M3Chunk] = None

    def _get_file(self) -> BinaryIO:
        """Get file handle, opening if needed."""
        if isinstance(self.source, (str, Path)):
            return open(self.source, "rb")
        # Assume file-like object, reset to start
        self.source.seek(0)
        return self.source

    def _load_chunks(self, file: BinaryIO) -> List[M3Chunk]:
        """Load and cache chunk index."""
        if self._chunks is None:
            file.seek(0)
            self._chunks = self.parser.parse_chunks(file)
        return self._chunks

    def _find_chunk(self, chunks: List[M3Chunk], chunk_id: str) -> M3Chunk:
        """Find chunk by ID."""
        return next((c for c in chunks if c.id == chunk_id), None)

    def get_vertices(self) -> List[Tuple[float, float, float]]:
        """Extract vertex positions from VPOS chunk.

        Returns:
            List of (x, y, z) tuples
        """
        file = self._get_file()
        try:
            chunks = self._load_chunks(file)

            vpos_chunk = self._find_chunk(chunks, "VPOS")
            if not vpos_chunk:
                return []

            file.seek(vpos_chunk.offset)
            data = file.read(vpos_chunk.size)

            # Parse as float32 triplets (12 bytes per vertex)
            vertices = []
            vertex_size = 12  # 3 floats * 4 bytes
            for i in range(0, len(data) - vertex_size + 1, vertex_size):
                x, y, z = struct.unpack("<fff", data[i : i + 12])
                vertices.append((x, y, z))

            return vertices
        finally:
            if isinstance(self.source, (str, Path)):
                file.close()

    def get_indices(self) -> List[int]:
        """Extract triangle indices from INDX chunk.

        Returns:
            List of vertex indices (every 3 form a triangle)
        """
        file = self._get_file()
        try:
            chunks = self._load_chunks(file)

            indx_chunk = self._find_chunk(chunks, "INDX")
            if not indx_chunk:
                return []

            file.seek(indx_chunk.offset)
            data = file.read(indx_chunk.size)

            # Parse as uint16 indices
            indices = []
            for i in range(0, len(data) - 1, 2):
                idx = struct.unpack("<H", data[i : i + 2])[0]
                indices.append(idx)

            return indices
        finally:
            if isinstance(self.source, (str, Path)):
                file.close()
