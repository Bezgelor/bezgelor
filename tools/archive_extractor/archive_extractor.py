"""WildStar Archive Extractor

Extracts files from WildStar .index/.archive pairs.
Based on reverse engineering of WildStar Studio source code.

Archive Format:
- .index file: Contains file tree, names, and metadata
- .archive file: Contains actual file data (optionally zlib compressed)

Usage:
    python archive_extractor.py <path_to.index> --list
    python archive_extractor.py <path_to.index> --extract "Art/Character/*.tex" -o ./output
    python archive_extractor.py <path_to.index> --extract-all -o ./output
"""
import argparse
import fnmatch
import hashlib
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Dict, List, Optional, Tuple


# Magic constants
PACK_MAGIC = 0x4B434150  # 'PACK' little-endian
AIDX_MAGIC = 0x58444941  # 'AIDX' little-endian
AARC_MAGIC = 0x43524141  # 'AARC' little-endian


@dataclass
class PackDirectoryHeader:
    """Block header in directory table."""
    offset: int      # 8 bytes
    block_size: int  # 8 bytes

    @classmethod
    def read(cls, f: BinaryIO) -> "PackDirectoryHeader":
        data = f.read(16)
        offset, block_size = struct.unpack("<QQ", data)
        return cls(offset=offset, block_size=block_size)


@dataclass
class FileEntry:
    """File entry metadata."""
    name: str
    full_path: str
    flags: int
    uncompressed_size: int
    compressed_size: int
    sha_hash: bytes

    def is_compressed(self) -> bool:
        return self.flags == 3


@dataclass
class AARCEntry:
    """Archive entry mapping hash to block."""
    block_index: int
    sha_hash: bytes
    uncompressed_size: int

    @classmethod
    def read(cls, f: BinaryIO) -> "AARCEntry":
        data = f.read(32)
        block_index = struct.unpack("<I", data[0:4])[0]
        sha_hash = data[4:24]
        uncompressed_size = struct.unpack("<Q", data[24:32])[0]
        return cls(block_index=block_index, sha_hash=sha_hash,
                   uncompressed_size=uncompressed_size)


class WildStarArchive:
    """Reader for WildStar .index/.archive file pairs."""

    def __init__(self, index_path: str):
        """Initialize with path to .index file.

        Args:
            index_path: Path to .index file. Archive file is assumed to be
                       same name with .archive extension.
        """
        self.index_path = Path(index_path)
        self.archive_path = self.index_path.with_suffix(".archive")

        if not self.index_path.exists():
            raise FileNotFoundError(f"Index file not found: {self.index_path}")
        if not self.archive_path.exists():
            raise FileNotFoundError(f"Archive file not found: {self.archive_path}")

        self._index_file: Optional[BinaryIO] = None
        self._archive_file: Optional[BinaryIO] = None

        # Parsed data
        self._index_blocks: List[PackDirectoryHeader] = []
        self._archive_blocks: List[PackDirectoryHeader] = []
        self._aarc_table: Dict[bytes, AARCEntry] = {}
        self._files: Dict[str, FileEntry] = {}
        self._root_block: int = 0

    def open(self):
        """Open archive files and parse headers."""
        self._index_file = open(self.index_path, "rb")
        self._archive_file = open(self.archive_path, "rb")

        self._parse_index_header()
        self._parse_archive_header()
        self._parse_file_tree()

    def close(self):
        """Close archive files."""
        if self._index_file:
            self._index_file.close()
        if self._archive_file:
            self._archive_file.close()

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def _parse_index_header(self):
        """Parse .index file header and block table."""
        f = self._index_file
        f.seek(0)

        # Check magic
        magic = struct.unpack("<I", f.read(4))[0]
        if magic != PACK_MAGIC:
            raise ValueError(f"Invalid index magic: {magic:#x}, expected PACK")

        version = struct.unpack("<I", f.read(4))[0]
        if version != 1:
            raise ValueError(f"Unsupported index version: {version}")

        # Read size data (548 bytes)
        f.read(528)  # Skip to directory info
        dir_table_start = struct.unpack("<Q", f.read(8))[0]
        dir_count = struct.unpack("<I", f.read(4))[0]
        f.read(8)  # Remaining padding

        # Read directory headers
        f.seek(dir_table_start)
        self._index_blocks = []
        for _ in range(dir_count):
            self._index_blocks.append(PackDirectoryHeader.read(f))

        # Find AIDX block
        for block in self._index_blocks:
            if block.block_size < 16:
                continue
            f.seek(block.offset)
            block_magic = struct.unpack("<I", f.read(4))[0]
            if block_magic == AIDX_MAGIC:
                f.read(4)  # version
                f.read(4)  # unk1
                self._root_block = struct.unpack("<I", f.read(4))[0]
                break
        else:
            raise ValueError("AIDX block not found in index")

    def _parse_archive_header(self):
        """Parse .archive file header and AARC table."""
        f = self._archive_file
        f.seek(0)

        # Check magic
        magic = struct.unpack("<I", f.read(4))[0]
        if magic != PACK_MAGIC:
            raise ValueError(f"Invalid archive magic: {magic:#x}")

        version = struct.unpack("<I", f.read(4))[0]
        if version != 1:
            raise ValueError(f"Unsupported archive version: {version}")

        # Read size data
        f.read(528)
        dir_table_start = struct.unpack("<Q", f.read(8))[0]
        dir_count = struct.unpack("<I", f.read(4))[0]
        f.read(8)

        # Read directory headers
        f.seek(dir_table_start)
        self._archive_blocks = []
        for _ in range(dir_count):
            self._archive_blocks.append(PackDirectoryHeader.read(f))

        # Find AARC block
        aarc_block = None
        aarc_entries = 0
        for block in self._archive_blocks:
            if block.block_size < 16:
                continue
            f.seek(block.offset)
            block_magic = struct.unpack("<I", f.read(4))[0]
            if block_magic == AARC_MAGIC:
                f.read(4)  # version
                aarc_entries = struct.unpack("<I", f.read(4))[0]
                aarc_table_block = struct.unpack("<I", f.read(4))[0]
                aarc_block = self._archive_blocks[aarc_table_block]
                break

        if not aarc_block:
            raise ValueError("AARC block not found in archive")

        # Read AARC entries
        f.seek(aarc_block.offset)
        self._aarc_table = {}
        for _ in range(aarc_entries):
            entry = AARCEntry.read(f)
            self._aarc_table[entry.sha_hash] = entry

    def _parse_file_tree(self):
        """Parse file tree from index."""
        self._files = {}
        self._parse_directory(self._root_block, "")

    def _parse_directory(self, block_index: int, path_prefix: str):
        """Recursively parse directory block."""
        f = self._index_file
        block = self._index_blocks[block_index]

        f.seek(block.offset)
        num_dirs = struct.unpack("<I", f.read(4))[0]
        num_files = struct.unpack("<I", f.read(4))[0]

        entries_start = f.tell()

        # Calculate string table position
        data_size = num_dirs * 8 + num_files * 56
        string_table_offset = entries_start + data_size
        string_table_size = block.block_size - 8 - data_size

        # Read string table
        f.seek(string_table_offset)
        string_data = f.read(int(string_table_size))

        # Parse directory entries
        f.seek(entries_start)
        subdirs = []
        for _ in range(num_dirs):
            name_offset = struct.unpack("<I", f.read(4))[0]
            next_block = struct.unpack("<I", f.read(4))[0]

            # Extract name from string table
            name_end = string_data.find(b'\x00', name_offset)
            name = string_data[name_offset:name_end].decode('utf-8', errors='replace')

            full_path = f"{path_prefix}{name}/" if path_prefix else f"{name}/"
            subdirs.append((next_block, full_path))

        # Parse file entries
        for _ in range(num_files):
            name_offset = struct.unpack("<I", f.read(4))[0]
            flags = struct.unpack("<I", f.read(4))[0]
            f.read(4)  # unk
            uncompressed_size = struct.unpack("<Q", f.read(8))[0]
            compressed_size = struct.unpack("<Q", f.read(8))[0]
            sha_hash = f.read(20)
            f.read(4)  # block (unused, we use AARC table)

            # Extract name
            name_end = string_data.find(b'\x00', name_offset)
            name = string_data[name_offset:name_end].decode('utf-8', errors='replace')

            full_path = f"{path_prefix}{name}"

            entry = FileEntry(
                name=name,
                full_path=full_path,
                flags=flags,
                uncompressed_size=uncompressed_size,
                compressed_size=compressed_size,
                sha_hash=sha_hash
            )
            self._files[full_path.lower()] = entry

        # Recurse into subdirectories
        for next_block, subdir_path in subdirs:
            self._parse_directory(next_block, subdir_path)

    def list_files(self, pattern: str = "*") -> List[str]:
        """List files matching pattern.

        Args:
            pattern: Glob pattern (e.g., "*.tex", "Art/Character/*.tex")

        Returns:
            List of matching file paths
        """
        pattern_lower = pattern.lower().replace("\\", "/")
        return [
            entry.full_path for entry in self._files.values()
            if fnmatch.fnmatch(entry.full_path.lower(), pattern_lower)
        ]

    def get_file_info(self, path: str) -> Optional[FileEntry]:
        """Get file entry by path."""
        return self._files.get(path.lower().replace("\\", "/"))

    def extract_file(self, path: str) -> Optional[bytes]:
        """Extract file data by path.

        Args:
            path: File path within archive

        Returns:
            File data bytes, or None if not found
        """
        entry = self.get_file_info(path)
        if not entry:
            return None

        # Find in AARC table
        aarc_entry = self._aarc_table.get(entry.sha_hash)
        if not aarc_entry:
            print(f"Warning: File not in AARC table: {path}")
            return None

        # Read from archive
        block = self._archive_blocks[aarc_entry.block_index]
        self._archive_file.seek(block.offset)
        compressed_data = self._archive_file.read(int(block.block_size))

        # Decompress if needed
        if entry.is_compressed():
            try:
                data = zlib.decompress(compressed_data)
                return data
            except zlib.error as e:
                print(f"Decompression failed for {path}: {e}")
                return None
        else:
            return compressed_data

    def extract_to_file(self, archive_path: str, output_path: str) -> bool:
        """Extract file to disk.

        Args:
            archive_path: Path within archive
            output_path: Output file path

        Returns:
            True if successful
        """
        data = self.extract_file(archive_path)
        if data is None:
            return False

        output = Path(output_path)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)
        return True


def main():
    parser = argparse.ArgumentParser(
        description="Extract files from WildStar archives"
    )
    parser.add_argument("index", help="Path to .index file")
    parser.add_argument("--list", "-l", metavar="PATTERN", nargs="?", const="*",
                       help="List files matching pattern (default: *)")
    parser.add_argument("--extract", "-e", metavar="PATTERN",
                       help="Extract files matching pattern")
    parser.add_argument("--extract-all", action="store_true",
                       help="Extract all files")
    parser.add_argument("--output", "-o", default="./output",
                       help="Output directory (default: ./output)")
    parser.add_argument("--info", "-i", metavar="PATH",
                       help="Show info for specific file")

    args = parser.parse_args()

    try:
        with WildStarArchive(args.index) as archive:
            if args.list is not None:
                files = archive.list_files(args.list)
                print(f"Found {len(files)} files matching '{args.list}':")
                for f in sorted(files)[:100]:
                    entry = archive.get_file_info(f)
                    comp = "zlib" if entry.is_compressed() else "raw"
                    print(f"  {f} ({entry.uncompressed_size:,} bytes, {comp})")
                if len(files) > 100:
                    print(f"  ... and {len(files) - 100} more")

            elif args.info:
                entry = archive.get_file_info(args.info)
                if entry:
                    print(f"File: {entry.full_path}")
                    print(f"  Flags: {entry.flags}")
                    print(f"  Compressed: {entry.is_compressed()}")
                    print(f"  Uncompressed size: {entry.uncompressed_size:,}")
                    print(f"  Compressed size: {entry.compressed_size:,}")
                    print(f"  SHA hash: {entry.sha_hash.hex()}")
                else:
                    print(f"File not found: {args.info}")

            elif args.extract or args.extract_all:
                pattern = args.extract if args.extract else "*"
                files = archive.list_files(pattern)
                print(f"Extracting {len(files)} files...")

                output_dir = Path(args.output)
                success = 0
                failed = 0

                for f in files:
                    output_path = output_dir / f
                    if archive.extract_to_file(f, str(output_path)):
                        success += 1
                        if success % 100 == 0:
                            print(f"  Extracted {success}/{len(files)}...")
                    else:
                        failed += 1

                print(f"Done: {success} extracted, {failed} failed")

            else:
                # Default: show stats
                all_files = archive.list_files("*")
                tex_files = archive.list_files("*.tex")
                m3_files = archive.list_files("*.m3")

                print(f"Archive: {args.index}")
                print(f"  Total files: {len(all_files):,}")
                print(f"  Texture files (.tex): {len(tex_files):,}")
                print(f"  Model files (.m3): {len(m3_files):,}")

    except Exception as e:
        print(f"Error: {e}")
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
