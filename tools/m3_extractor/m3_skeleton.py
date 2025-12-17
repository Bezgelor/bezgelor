"""Skeleton/bone extraction from M3 model files."""
import struct
from typing import BinaryIO, Dict, List, Tuple, Union
from pathlib import Path

from m3_parser import M3Parser
from m3_types import M3Chunk


class M3SkeletonExtractor:
    """Extracts skeleton/bone data from M3 files."""

    # Bone entry size: id(4) + parent_id(4) + transform(64) = 72 bytes
    BONE_SIZE = 72

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

    def get_bones(self) -> List[Dict]:
        """Extract bone hierarchy from BONE chunk.

        Returns:
            List of bone dictionaries with:
            - id: Bone index
            - parent_id: Parent bone index (-1 for root)
            - transform: 4x4 transformation matrix as 16 floats
        """
        file = self._get_file()
        try:
            chunks = self._load_chunks(file)

            bone_chunk = self._find_chunk(chunks, "BONE")
            if not bone_chunk:
                return []

            file.seek(bone_chunk.offset)
            data = file.read(bone_chunk.size)

            bones = []
            for i in range(0, len(data) - self.BONE_SIZE + 1, self.BONE_SIZE):
                bone_id = struct.unpack("<I", data[i : i + 4])[0]
                parent_id = struct.unpack("<i", data[i + 4 : i + 8])[0]
                transform = struct.unpack("<16f", data[i + 8 : i + 72])

                bones.append(
                    {
                        "id": bone_id,
                        "parent_id": parent_id,
                        "transform": list(transform),
                    }
                )

            return bones
        finally:
            if isinstance(self.source, (str, Path)):
                file.close()

    def get_bone_names(self) -> Dict[int, str]:
        """Get bone names from string table if available.

        Returns:
            Dictionary mapping bone ID to name
        """
        # TODO: Parse M3ST (string table) chunk for bone names
        return {}
