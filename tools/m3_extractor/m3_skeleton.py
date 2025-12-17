"""Skeleton/bone extraction from WildStar M3 model files.

WildStar M3 format bone structure (based on NexusVault-Java):
- Header size: 0x630 (1584) bytes
- Bone pointer at header offset 0x180: {count: int64, offset: int64}
- Bone data starts at: header_end + offset
- Each bone is 0x160 (352) bytes:
  - +0x004: parentId (int16, -1 = root bone)
  - +0x0D0: transformation matrix (16 floats, column-major)
  - +0x110: inverse transformation matrix (16 floats, column-major)
  - +0x150: x position (float)
  - +0x154: y position (float)
  - +0x158: z position (float)
"""
import struct
from dataclasses import dataclass, field
from typing import BinaryIO, Dict, List, Optional, Tuple, Union
from pathlib import Path


@dataclass
class Bone:
    """Represents a bone in the skeleton hierarchy."""
    index: int
    parent_id: int  # -1 for root bones
    position: Tuple[float, float, float]
    transform_matrix: List[float]  # 4x4 column-major matrix (16 floats)
    inverse_matrix: List[float]  # 4x4 column-major inverse matrix

    @property
    def is_root(self) -> bool:
        return self.parent_id == -1


@dataclass
class Skeleton:
    """Complete skeleton extracted from M3 file."""
    bones: List[Bone] = field(default_factory=list)

    @property
    def bone_count(self) -> int:
        return len(self.bones)

    @property
    def root_bones(self) -> List[Bone]:
        return [b for b in self.bones if b.is_root]

    def get_bone(self, index: int) -> Optional[Bone]:
        """Get bone by index."""
        if 0 <= index < len(self.bones):
            return self.bones[index]
        return None

    def get_children(self, bone: Bone) -> List[Bone]:
        """Get direct children of a bone."""
        return [b for b in self.bones if b.parent_id == bone.index]

    def get_hierarchy_depth(self, bone: Bone) -> int:
        """Get depth of bone in hierarchy (0 for root)."""
        depth = 0
        current = bone
        while current.parent_id != -1:
            depth += 1
            current = self.get_bone(current.parent_id)
            if current is None:
                break
        return depth

    def to_dict_list(self) -> List[Dict]:
        """Convert to list of dictionaries for glTF export compatibility."""
        return [
            {
                "id": bone.index,
                "parent_id": bone.parent_id,
                "transform": bone.transform_matrix,
                "position": list(bone.position),
            }
            for bone in self.bones
        ]


class M3SkeletonExtractor:
    """Extracts skeleton/bone data from WildStar M3 files."""

    MAGIC_LDOM = 1297040460  # "LDOM" as int32 little-endian
    HEADER_SIZE = 0x630  # 1584 bytes
    BONE_POINTER_OFFSET = 0x180  # Offset in header to bone pointer
    BONE_STRUCT_SIZE = 0x160  # 352 bytes per bone

    # Bone struct field offsets
    BONE_PARENT_ID_OFFSET = 0x004
    BONE_TRANSFORM_OFFSET = 0x0D0
    BONE_INVERSE_OFFSET = 0x110
    BONE_POSITION_OFFSET = 0x150

    def __init__(self, source: Union[str, Path, BinaryIO]):
        """Initialize extractor with file path or file-like object.

        Args:
            source: Path to M3 file or file-like object
        """
        self.source = source
        self._skeleton: Optional[Skeleton] = None
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
        """Parse M3 file and extract skeleton data."""
        if self._parsed:
            return

        file = self._get_file()
        try:
            # Check magic
            magic = struct.unpack("<i", file.read(4))[0]
            if magic != self.MAGIC_LDOM:
                self._skeleton = Skeleton()
                self._parsed = True
                return

            # Read bone pointer from header
            file.seek(self.BONE_POINTER_OFFSET)
            bone_count = struct.unpack("<q", file.read(8))[0]
            bone_offset = struct.unpack("<q", file.read(8))[0]

            if bone_count <= 0:
                self._skeleton = Skeleton()
                self._parsed = True
                return

            # Calculate absolute bone data position
            bone_data_start = self.HEADER_SIZE + bone_offset

            # Validate offset
            file.seek(0, 2)
            file_size = file.tell()
            expected_end = bone_data_start + (bone_count * self.BONE_STRUCT_SIZE)

            if bone_data_start >= file_size or expected_end > file_size:
                print(f"Warning: Bone data extends beyond file")
                print(f"  File size: {file_size}")
                print(f"  Bone start: {bone_data_start}")
                print(f"  Expected end: {expected_end}")
                self._skeleton = Skeleton()
                self._parsed = True
                return

            # Parse each bone
            bones = []
            for i in range(bone_count):
                bone_start = bone_data_start + (i * self.BONE_STRUCT_SIZE)
                file.seek(bone_start)

                # Read full bone struct
                bone_data = file.read(self.BONE_STRUCT_SIZE)
                if len(bone_data) < self.BONE_STRUCT_SIZE:
                    break

                # Parse parent ID (int16 at offset 0x004)
                parent_id = struct.unpack("<h", bone_data[0x004:0x006])[0]

                # Parse transform matrix (16 floats at offset 0x0D0)
                transform_data = bone_data[0x0D0:0x0D0 + 64]
                transform_matrix = list(struct.unpack("<16f", transform_data))

                # Parse inverse matrix (16 floats at offset 0x110)
                inverse_data = bone_data[0x110:0x110 + 64]
                inverse_matrix = list(struct.unpack("<16f", inverse_data))

                # Parse position (3 floats at offset 0x150)
                x = struct.unpack("<f", bone_data[0x150:0x154])[0]
                y = struct.unpack("<f", bone_data[0x154:0x158])[0]
                z = struct.unpack("<f", bone_data[0x158:0x15C])[0]

                bone = Bone(
                    index=i,
                    parent_id=parent_id,
                    position=(x, y, z),
                    transform_matrix=transform_matrix,
                    inverse_matrix=inverse_matrix
                )
                bones.append(bone)

            self._skeleton = Skeleton(bones=bones)
            self._parsed = True

        except Exception as e:
            print(f"Skeleton parse error: {e}")
            import traceback
            traceback.print_exc()
            self._skeleton = Skeleton()
            self._parsed = True

        finally:
            self._close_file(file)

    def get_skeleton(self) -> Skeleton:
        """Extract complete skeleton from M3 file.

        Returns:
            Skeleton object with all bones
        """
        self._parse()
        return self._skeleton

    def get_bones(self) -> List[Dict]:
        """Extract bones as list of dictionaries (legacy interface).

        Returns:
            List of bone dictionaries with id, parent_id, transform
        """
        self._parse()
        return self._skeleton.to_dict_list()

    def print_hierarchy(self):
        """Print bone hierarchy to console."""
        self._parse()
        skeleton = self._skeleton

        print(f"Skeleton: {skeleton.bone_count} bones")
        print(f"Root bones: {len(skeleton.root_bones)}")
        print()

        def print_bone(bone: Bone, indent: int = 0):
            prefix = "  " * indent
            pos = bone.position
            print(f"{prefix}[{bone.index}] pos=({pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})")
            for child in skeleton.get_children(bone):
                print_bone(child, indent + 1)

        for root in skeleton.root_bones:
            print_bone(root)


def main():
    """Command-line interface for skeleton extraction."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Extract skeleton/bones from WildStar M3 model files"
    )
    parser.add_argument("input", help="Input M3 file")
    parser.add_argument("--hierarchy", "-H", action="store_true",
                       help="Print bone hierarchy")
    parser.add_argument("--json", "-j", action="store_true",
                       help="Output bones as JSON")

    args = parser.parse_args()

    extractor = M3SkeletonExtractor(args.input)
    skeleton = extractor.get_skeleton()

    if args.json:
        import json
        bones_data = []
        for bone in skeleton.bones:
            bones_data.append({
                "index": bone.index,
                "parent_id": bone.parent_id,
                "position": list(bone.position),
                "transform": bone.transform_matrix,
                "inverse": bone.inverse_matrix
            })
        print(json.dumps({"bone_count": skeleton.bone_count, "bones": bones_data}, indent=2))
    elif args.hierarchy:
        extractor.print_hierarchy()
    else:
        print(f"File: {args.input}")
        print(f"Bones: {skeleton.bone_count}")
        print(f"Root bones: {len(skeleton.root_bones)}")

        if skeleton.bone_count > 0:
            print("\nBone summary:")
            max_depth = max(skeleton.get_hierarchy_depth(b) for b in skeleton.bones)
            print(f"  Max hierarchy depth: {max_depth}")

            # Show first few bones
            print("\nFirst 10 bones:")
            for bone in skeleton.bones[:10]:
                depth = skeleton.get_hierarchy_depth(bone)
                print(f"  [{bone.index}] parent={bone.parent_id} depth={depth} "
                      f"pos=({bone.position[0]:.3f}, {bone.position[1]:.3f}, {bone.position[2]:.3f})")


if __name__ == "__main__":
    main()
