"""Animation extraction from M3 model files."""
import struct
from typing import BinaryIO, Dict, List, Tuple, Union
from pathlib import Path

from m3_parser import M3Parser
from m3_types import M3Chunk


class M3AnimationExtractor:
    """Extracts animation data from M3 files."""

    # Animation header: id(4) + duration(4) + keyframe_count(4) + keyframe_offset(4) = 16 bytes
    ANIM_HEADER_SIZE = 16
    # Keyframe: time(4) + bone_id(4) + position(12) + rotation(16) = 36 bytes
    KEYFRAME_SIZE = 36

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

    def get_animations(self) -> List[Dict]:
        """Extract animation data from ANIM chunk.

        Returns:
            List of animation dictionaries with:
            - id: Animation ID
            - duration: Duration in seconds
            - keyframes: List of keyframe data
        """
        file = self._get_file()
        try:
            chunks = self._load_chunks(file)

            anim_chunk = self._find_chunk(chunks, "ANIM")
            if not anim_chunk:
                return []

            keyf_chunk = self._find_chunk(chunks, "KEYF")

            # Read animation headers
            file.seek(anim_chunk.offset)
            anim_data = file.read(anim_chunk.size)

            # Read keyframe data if available
            keyframe_data = b""
            if keyf_chunk:
                file.seek(keyf_chunk.offset)
                keyframe_data = file.read(keyf_chunk.size)

            animations = []
            anim_count = anim_chunk.property_a if anim_chunk.property_a > 0 else (
                anim_chunk.size // self.ANIM_HEADER_SIZE
            )

            for i in range(anim_count):
                offset = i * self.ANIM_HEADER_SIZE
                if offset + self.ANIM_HEADER_SIZE > len(anim_data):
                    break

                anim_id = struct.unpack("<I", anim_data[offset:offset + 4])[0]
                duration = struct.unpack("<f", anim_data[offset + 4:offset + 8])[0]
                kf_count = struct.unpack("<I", anim_data[offset + 8:offset + 12])[0]
                kf_offset = struct.unpack("<I", anim_data[offset + 12:offset + 16])[0]

                keyframes = self._parse_keyframes(keyframe_data, kf_offset, kf_count)

                animations.append({
                    "id": anim_id,
                    "duration": duration,
                    "keyframes": keyframes,
                })

            return animations
        finally:
            if isinstance(self.source, (str, Path)):
                file.close()

    def _parse_keyframes(self, data: bytes, offset: int, count: int) -> List[Dict]:
        """Parse keyframe data.

        Args:
            data: Raw keyframe data
            offset: Byte offset to start of keyframes
            count: Number of keyframes

        Returns:
            List of keyframe dictionaries
        """
        keyframes = []
        for i in range(count):
            kf_offset = offset + i * self.KEYFRAME_SIZE
            if kf_offset + self.KEYFRAME_SIZE > len(data):
                break

            time = struct.unpack("<f", data[kf_offset:kf_offset + 4])[0]
            bone_id = struct.unpack("<I", data[kf_offset + 4:kf_offset + 8])[0]
            position = struct.unpack("<3f", data[kf_offset + 8:kf_offset + 20])
            rotation = struct.unpack("<4f", data[kf_offset + 20:kf_offset + 36])

            keyframes.append({
                "time": time,
                "bone_id": bone_id,
                "position": list(position),
                "rotation": list(rotation),
            })

        return keyframes
