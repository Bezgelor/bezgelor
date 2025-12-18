"""Parser for WildStar M3 model files."""
import struct
from typing import BinaryIO, List

from m3_types import M3Header, M3Chunk


class M3Parser:
    """Parses WildStar M3 model files."""

    # Known valid magic bytes for M3 files
    VALID_MAGIC = [b"LDOM", b"43MD", b"MD34"]

    def parse_header(self, file: BinaryIO) -> M3Header:
        """Parse M3 header from file.

        Args:
            file: Open binary file handle

        Returns:
            M3Header with parsed data

        Raises:
            ValueError: If magic bytes are invalid
        """
        data = file.read(16)
        return self.parse_header_bytes(data)

    def parse_header_bytes(self, data: bytes) -> M3Header:
        """Parse M3 header from bytes.

        Args:
            data: At least 16 bytes of header data

        Returns:
            M3Header with parsed data

        Raises:
            ValueError: If magic bytes are invalid
        """
        if len(data) < 8:
            raise ValueError("Header data too short")

        magic = data[:4]
        if magic not in self.VALID_MAGIC:
            raise ValueError(f"Invalid M3 magic: {magic}")

        version = struct.unpack("<I", data[4:8])[0]

        # Parse additional header fields if available
        index_offset = 0
        index_count = 0
        if len(data) >= 16:
            index_offset, index_count = struct.unpack("<II", data[8:16])

        return M3Header(
            magic=magic,
            version=version,
            index_offset=index_offset,
            index_count=index_count,
        )

    def parse_chunks(self, file: BinaryIO) -> List[M3Chunk]:
        """Parse chunk index from M3 file.

        Args:
            file: Open binary file handle positioned at start

        Returns:
            List of M3Chunk objects describing each chunk
        """
        # Parse header first to get chunk index location
        header = self.parse_header(file)

        if header.index_count == 0:
            return []

        # Seek to chunk index
        file.seek(header.index_offset)

        chunks = []
        for _ in range(header.index_count):
            chunk_data = file.read(16)
            if len(chunk_data) < 16:
                break

            # Parse chunk header: id (4 bytes), offset, size, property_a
            chunk_id = chunk_data[:4].decode("ascii", errors="replace")
            offset, size, property_a = struct.unpack("<III", chunk_data[4:16])

            chunks.append(
                M3Chunk(
                    id=chunk_id,
                    offset=offset,
                    size=size,
                    property_a=property_a,
                )
            )

        return chunks
