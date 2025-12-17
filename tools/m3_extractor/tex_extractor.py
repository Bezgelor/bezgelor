"""Extractor for WildStar .tex texture files.

WildStar TEX Format:
- 32-byte header with magic "XFG\0"
- Supports DXT1, DXT3, DXT5 compressed and uncompressed formats
- Mipmaps stored smallest-to-largest (opposite of DDS)

Type-3 Textures (most WildStar textures):
- Type-3 with DXT format + count=0: 80 bytes padding, then standard DXT data
- Type-3 with format=0 + count>0: Custom compressed format (not yet supported)
  - Has secondary header with: count, padding, 4 RGB colors, mip offsets
  - Data uses unknown compression (possibly BC7 with additional streaming compression)
"""
import struct
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import BinaryIO, Optional, Tuple


class TexFormat(IntEnum):
    """Texture format types.

    Note: WildStar textures with type=3 use a custom block compression
    format that is not yet fully understood. Format 0 in type=3 textures
    appears to be BC7-like, not uncompressed BGRA.
    """
    UNCOMPRESSED_RGBA = 0
    UNCOMPRESSED_RGB = 1
    DXT1 = 13
    DXT3 = 14
    DXT5 = 15


class TexType(IntEnum):
    """Texture type values."""
    STANDARD = 0     # Standard DXT-compressed textures
    TYPE_3 = 3       # Custom block compression (BC7-like, not yet supported)


@dataclass
class TexHeader:
    """WildStar TEX file header (32 bytes).

    Based on WildStar Wiki documentation:
    https://wildstaronline-archive.fandom.com/wiki/TEX_file
    """
    magic: bytes           # 4 bytes: "XFG\0"
    tex_type: int          # 4 bytes: always 0 (or 3 in some files)
    width: int             # 4 bytes: power of 2
    height: int            # 4 bytes: power of 2
    depth: int             # 4 bytes: typically 1
    sides: int             # 4 bytes: typically 1 (6 for cubemaps)
    mip_count: int         # 4 bytes: number of mipmaps
    format: TexFormat      # 4 bytes: compression type

    @classmethod
    def read(cls, file: BinaryIO) -> "TexHeader":
        """Read TEX header from file."""
        data = file.read(32)
        if len(data) < 32:
            raise ValueError("File too small for TEX header")

        magic = data[:4]
        if magic not in (b"XFG\0", b"\0GFX"):
            raise ValueError(f"Invalid TEX magic: {magic!r}")

        values = struct.unpack("<IIIIIII", data[4:32])
        format_val = values[6]
        return cls(
            magic=magic,
            tex_type=values[0],
            width=values[1],
            height=values[2],
            depth=values[3],
            sides=values[4],
            mip_count=values[5],
            format=TexFormat(format_val) if format_val in [e.value for e in TexFormat] else format_val,
        )


class TexExtractor:
    """Extracts WildStar .tex texture files to standard formats."""

    # Size of type-3 secondary header for simple DXT textures (count=0)
    TYPE3_SIMPLE_HEADER_SIZE = 80

    def __init__(self, filepath: str):
        """Initialize extractor with path to .tex file.

        Args:
            filepath: Path to .tex file
        """
        self.filepath = Path(filepath)
        self.header: Optional[TexHeader] = None
        self._data: Optional[bytes] = None
        self._type3_count: int = 0  # For type-3: 0 = simple DXT, >0 = custom compression

    def load(self) -> bool:
        """Load and parse the TEX file.

        Returns:
            True if successful, False otherwise
        """
        try:
            with open(self.filepath, "rb") as f:
                self.header = TexHeader.read(f)
                self._data = f.read()

            # Parse type-3 secondary header
            if self.header.tex_type == 3 and len(self._data) >= 4:
                self._type3_count = struct.unpack('<I', self._data[0:4])[0]

            return True
        except Exception as e:
            print(f"Failed to load TEX: {e}")
            return False

    def _get_texture_data_offset(self) -> int:
        """Get offset to actual texture data within _data.

        For type-3 textures with count=0, skips 80-byte secondary header.
        """
        if self.header.tex_type == 3 and self._type3_count == 0:
            return self.TYPE3_SIMPLE_HEADER_SIZE
        return 0

    def _is_simple_type3(self) -> bool:
        """Check if this is a simple type-3 texture (DXT with count=0)."""
        return (self.header.tex_type == 3 and
                self._type3_count == 0 and
                self.header.format in (TexFormat.DXT1, TexFormat.DXT3, TexFormat.DXT5))

    def get_info(self) -> dict:
        """Get texture information.

        Returns:
            Dictionary with texture metadata
        """
        if not self.header:
            self.load()

        info = {
            "filepath": str(self.filepath),
            "width": self.header.width,
            "height": self.header.height,
            "format": self._format_name(self.header.format),
            "mip_count": self.header.mip_count,
            "type": self.header.tex_type,
            "depth": self.header.depth,
            "sides": self.header.sides,
        }

        # Add type-3 specific info
        if self.header.tex_type == 3:
            info["type3_count"] = self._type3_count
            info["type3_simple"] = self._is_simple_type3()

        return info

    def _format_name(self, fmt) -> str:
        """Get human-readable format name."""
        if isinstance(fmt, TexFormat):
            return fmt.name
        return f"UNKNOWN({fmt})"

    def _calc_mip_size(self, width: int, height: int, fmt) -> int:
        """Calculate size of a mipmap level.

        Args:
            width: Mip width
            height: Mip height
            fmt: Texture format

        Returns:
            Size in bytes
        """
        if fmt == TexFormat.DXT1:
            # DXT1: 4x4 blocks, 8 bytes per block
            blocks_x = max(1, (width + 3) // 4)
            blocks_y = max(1, (height + 3) // 4)
            return blocks_x * blocks_y * 8
        elif fmt in (TexFormat.DXT3, TexFormat.DXT5):
            # DXT3/5: 4x4 blocks, 16 bytes per block
            blocks_x = max(1, (width + 3) // 4)
            blocks_y = max(1, (height + 3) // 4)
            return blocks_x * blocks_y * 16
        elif fmt == TexFormat.UNCOMPRESSED_RGBA:
            return width * height * 4
        elif fmt == TexFormat.UNCOMPRESSED_RGB:
            return width * height * 3
        else:
            # Unknown format, estimate
            return width * height * 4

    def get_mipmap_offsets(self) -> list:
        """Calculate offsets and sizes for each mipmap level.

        WildStar stores mipmaps smallest-to-largest (opposite of DDS).
        For type-3 simple textures, offsets account for 80-byte secondary header.

        Returns:
            List of (offset, size, width, height) tuples, from largest to smallest
        """
        if not self.header:
            self.load()

        mips = []
        # Start offset accounts for type-3 secondary header if present
        base_offset = self._get_texture_data_offset()
        offset = base_offset

        # For simple type-3, we only have 1 mip (largest)
        if self._is_simple_type3():
            size = self._calc_mip_size(self.header.width, self.header.height, self.header.format)
            return [(base_offset, size, self.header.width, self.header.height)]

        # Calculate all mip dimensions (smallest to largest, as stored)
        mip_dims = []
        w, h = self.header.width, self.header.height
        for _ in range(self.header.mip_count):
            mip_dims.append((w, h))
            w = max(1, w // 2)
            h = max(1, h // 2)

        # Reverse to get storage order (smallest first)
        mip_dims = list(reversed(mip_dims))

        for w, h in mip_dims:
            size = self._calc_mip_size(w, h, self.header.format)
            mips.append((offset, size, w, h))
            offset += size

        # Return in standard order (largest first)
        return list(reversed(mips))

    def extract_largest_mip(self) -> Tuple[bytes, int, int]:
        """Extract the largest mipmap level.

        Returns:
            Tuple of (data, width, height)
        """
        if not self.header or not self._data:
            self.load()

        mips = self.get_mipmap_offsets()
        if not mips:
            raise ValueError("No mipmaps found")

        # First entry is largest
        offset, size, width, height = mips[0]
        data = self._data[offset:offset + size]

        return data, width, height

    def to_dds(self, output_path: str) -> bool:
        """Export texture as DDS file.

        Args:
            output_path: Path for output DDS file

        Returns:
            True if successful
        """
        if not self.header or not self._data:
            self.load()

        try:
            with open(output_path, "wb") as f:
                # DDS magic
                f.write(b"DDS ")

                # DDS header (124 bytes)
                header = self._build_dds_header()
                f.write(header)

                # For DXT formats, need DX10 extended header
                # For now, use standard DDS

                # Texture data - reverse mipmap order for DDS (largest first)
                mips = self.get_mipmap_offsets()
                for offset, size, w, h in mips:
                    f.write(self._data[offset:offset + size])

            return True
        except Exception as e:
            print(f"Failed to write DDS: {e}")
            return False

    def _build_dds_header(self) -> bytes:
        """Build DDS file header (124 bytes)."""
        # DDS_HEADER structure
        dwSize = 124
        dwFlags = 0x1 | 0x2 | 0x4 | 0x1000  # CAPS | HEIGHT | WIDTH | PIXELFORMAT
        if self.header.mip_count > 1:
            dwFlags |= 0x20000  # MIPMAPCOUNT

        dwHeight = self.header.height
        dwWidth = self.header.width
        dwPitchOrLinearSize = self._calc_mip_size(dwWidth, dwHeight, self.header.format)
        dwDepth = 0
        dwMipMapCount = self.header.mip_count

        # Reserved1 (11 DWORDs)
        reserved1 = b"\x00" * 44

        # DDS_PIXELFORMAT (32 bytes)
        pfSize = 32
        pfFlags = 0x4  # FOURCC
        fourCC = self._get_fourcc()
        pfRGBBitCount = 0
        pfRBitMask = 0
        pfGBitMask = 0
        pfBBitMask = 0
        pfABitMask = 0

        if self.header.format in (TexFormat.UNCOMPRESSED_RGBA, TexFormat.UNCOMPRESSED_RGB):
            pfFlags = 0x40  # RGB
            if self.header.format == TexFormat.UNCOMPRESSED_RGBA:
                pfFlags |= 0x1  # ALPHAPIXELS
                pfRGBBitCount = 32
                pfRBitMask = 0x00FF0000
                pfGBitMask = 0x0000FF00
                pfBBitMask = 0x000000FF
                pfABitMask = 0xFF000000
            else:
                pfRGBBitCount = 24
                pfRBitMask = 0x00FF0000
                pfGBitMask = 0x0000FF00
                pfBBitMask = 0x000000FF

        pixel_format = struct.pack(
            "<IIIIIIII",
            pfSize, pfFlags, fourCC, pfRGBBitCount,
            pfRBitMask, pfGBitMask, pfBBitMask, pfABitMask
        )

        # Caps
        dwCaps = 0x1000  # TEXTURE
        if self.header.mip_count > 1:
            dwCaps |= 0x8 | 0x400000  # COMPLEX | MIPMAP
        dwCaps2 = 0
        dwCaps3 = 0
        dwCaps4 = 0
        dwReserved2 = 0

        header = struct.pack(
            "<IIIIIII",
            dwSize, dwFlags, dwHeight, dwWidth,
            dwPitchOrLinearSize, dwDepth, dwMipMapCount
        )
        header += reserved1
        header += pixel_format
        header += struct.pack("<IIIII", dwCaps, dwCaps2, dwCaps3, dwCaps4, dwReserved2)

        return header

    def _get_fourcc(self) -> int:
        """Get FourCC code for texture format."""
        if self.header.format == TexFormat.DXT1:
            return 0x31545844  # "DXT1"
        elif self.header.format == TexFormat.DXT3:
            return 0x33545844  # "DXT3"
        elif self.header.format == TexFormat.DXT5:
            return 0x35545844  # "DXT5"
        else:
            return 0  # Uncompressed

    def to_png(self, output_path: str) -> bool:
        """Export texture as PNG file.

        Requires Pillow for decompression.

        Args:
            output_path: Path for output PNG file

        Returns:
            True if successful
        """
        try:
            from PIL import Image
        except ImportError:
            print("Pillow required for PNG export. Install with: pip install Pillow")
            return False

        if not self.header or not self._data:
            self.load()

        # Check for unsupported type 3 textures with custom compression
        if self.header.tex_type == 3 and not self._is_simple_type3():
            print(f"Type 3 textures with custom compression not yet supported.")
            print(f"  Dimensions: {self.header.width}x{self.header.height}")
            print(f"  Format: {self._format_name(self.header.format)}")
            print(f"  Count: {self._type3_count}")
            print(f"  Use --format dds to export raw data for external conversion.")
            return False

        try:
            # Get largest mipmap
            data, width, height = self.extract_largest_mip()

            if self.header.format in (TexFormat.DXT1, TexFormat.DXT3, TexFormat.DXT5):
                # Decompress DXT
                rgba = self._decompress_dxt(data, width, height)
                img = Image.frombytes("RGBA", (width, height), rgba)
            elif self.header.format == TexFormat.UNCOMPRESSED_RGBA:
                img = Image.frombytes("RGBA", (width, height), data)
            elif self.header.format == TexFormat.UNCOMPRESSED_RGB:
                img = Image.frombytes("RGB", (width, height), data)
            else:
                print(f"Unsupported format: {self.header.format}")
                return False

            img.save(output_path, "PNG")
            return True

        except Exception as e:
            print(f"Failed to write PNG: {e}")
            return False

    def _decompress_dxt(self, data: bytes, width: int, height: int) -> bytes:
        """Decompress DXT-compressed data to RGBA.

        Args:
            data: Compressed data
            width: Image width
            height: Image height

        Returns:
            Decompressed RGBA data
        """
        # Use simple DXT decompression
        if self.header.format == TexFormat.DXT1:
            return self._decompress_dxt1(data, width, height)
        elif self.header.format == TexFormat.DXT5:
            return self._decompress_dxt5(data, width, height)
        elif self.header.format == TexFormat.DXT3:
            return self._decompress_dxt3(data, width, height)
        else:
            raise ValueError(f"Cannot decompress format: {self.header.format}")

    def _decompress_dxt1(self, data: bytes, width: int, height: int) -> bytes:
        """Decompress DXT1 data."""
        result = bytearray(width * height * 4)
        blocks_x = (width + 3) // 4
        blocks_y = (height + 3) // 4

        for by in range(blocks_y):
            for bx in range(blocks_x):
                block_offset = (by * blocks_x + bx) * 8
                if block_offset + 8 > len(data):
                    break
                block = data[block_offset:block_offset + 8]
                self._decode_dxt1_block(block, result, bx * 4, by * 4, width, height)

        return bytes(result)

    def _decode_dxt1_block(self, block: bytes, result: bytearray,
                           start_x: int, start_y: int, width: int, height: int):
        """Decode a single DXT1 4x4 block."""
        # Two 16-bit colors
        c0 = struct.unpack("<H", block[0:2])[0]
        c1 = struct.unpack("<H", block[2:4])[0]

        # Expand to RGB888
        colors = [
            self._rgb565_to_rgba(c0),
            self._rgb565_to_rgba(c1),
            (0, 0, 0, 255),
            (0, 0, 0, 255),
        ]

        if c0 > c1:
            # 4-color block
            colors[2] = self._interpolate_color(colors[0], colors[1], 1, 3)
            colors[3] = self._interpolate_color(colors[0], colors[1], 2, 3)
        else:
            # 3-color block + transparent
            colors[2] = self._interpolate_color(colors[0], colors[1], 1, 2)
            colors[3] = (0, 0, 0, 0)

        # 4 bytes of 2-bit indices
        indices = struct.unpack("<I", block[4:8])[0]

        for y in range(4):
            for x in range(4):
                px, py = start_x + x, start_y + y
                if px < width and py < height:
                    idx = (indices >> ((y * 4 + x) * 2)) & 0x3
                    color = colors[idx]
                    offset = (py * width + px) * 4
                    result[offset:offset + 4] = bytes(color)

    def _rgb565_to_rgba(self, color: int) -> tuple:
        """Convert RGB565 to RGBA tuple."""
        r = ((color >> 11) & 0x1F) * 255 // 31
        g = ((color >> 5) & 0x3F) * 255 // 63
        b = (color & 0x1F) * 255 // 31
        return (r, g, b, 255)

    def _interpolate_color(self, c0: tuple, c1: tuple, num: int, denom: int) -> tuple:
        """Interpolate between two colors."""
        return tuple(
            (c0[i] * (denom - num) + c1[i] * num) // denom
            for i in range(4)
        )

    def _decompress_dxt3(self, data: bytes, width: int, height: int) -> bytes:
        """Decompress DXT3 data."""
        result = bytearray(width * height * 4)
        blocks_x = (width + 3) // 4
        blocks_y = (height + 3) // 4

        for by in range(blocks_y):
            for bx in range(blocks_x):
                block_offset = (by * blocks_x + bx) * 16
                if block_offset + 16 > len(data):
                    break
                block = data[block_offset:block_offset + 16]
                self._decode_dxt3_block(block, result, bx * 4, by * 4, width, height)

        return bytes(result)

    def _decode_dxt3_block(self, block: bytes, result: bytearray,
                           start_x: int, start_y: int, width: int, height: int):
        """Decode a single DXT3 4x4 block."""
        # 8 bytes of explicit alpha
        alpha_data = block[0:8]

        # DXT1 color block
        c0 = struct.unpack("<H", block[8:10])[0]
        c1 = struct.unpack("<H", block[10:12])[0]

        colors = [
            self._rgb565_to_rgba(c0),
            self._rgb565_to_rgba(c1),
            self._interpolate_color(self._rgb565_to_rgba(c0),
                                   self._rgb565_to_rgba(c1), 1, 3),
            self._interpolate_color(self._rgb565_to_rgba(c0),
                                   self._rgb565_to_rgba(c1), 2, 3),
        ]

        indices = struct.unpack("<I", block[12:16])[0]

        for y in range(4):
            for x in range(4):
                px, py = start_x + x, start_y + y
                if px < width and py < height:
                    idx = (indices >> ((y * 4 + x) * 2)) & 0x3
                    r, g, b, _ = colors[idx]

                    # Get alpha from explicit data
                    alpha_byte = alpha_data[(y * 4 + x) // 2]
                    if (y * 4 + x) % 2 == 0:
                        alpha = (alpha_byte & 0x0F) * 17
                    else:
                        alpha = ((alpha_byte >> 4) & 0x0F) * 17

                    offset = (py * width + px) * 4
                    result[offset:offset + 4] = bytes((r, g, b, alpha))

    def _decompress_dxt5(self, data: bytes, width: int, height: int) -> bytes:
        """Decompress DXT5 data."""
        result = bytearray(width * height * 4)
        blocks_x = (width + 3) // 4
        blocks_y = (height + 3) // 4

        for by in range(blocks_y):
            for bx in range(blocks_x):
                block_offset = (by * blocks_x + bx) * 16
                if block_offset + 16 > len(data):
                    break
                block = data[block_offset:block_offset + 16]
                self._decode_dxt5_block(block, result, bx * 4, by * 4, width, height)

        return bytes(result)

    def _decode_dxt5_block(self, block: bytes, result: bytearray,
                           start_x: int, start_y: int, width: int, height: int):
        """Decode a single DXT5 4x4 block."""
        # 2 alpha endpoints + 48-bit indices
        alpha0, alpha1 = block[0], block[1]

        # Build alpha palette
        alphas = [alpha0, alpha1, 0, 0, 0, 0, 0, 0]
        if alpha0 > alpha1:
            for i in range(6):
                alphas[2 + i] = ((6 - i) * alpha0 + (1 + i) * alpha1) // 7
        else:
            for i in range(4):
                alphas[2 + i] = ((4 - i) * alpha0 + (1 + i) * alpha1) // 5
            alphas[6] = 0
            alphas[7] = 255

        # 6 bytes of 3-bit alpha indices
        alpha_indices = struct.unpack("<Q", block[0:8])[0] >> 16

        # DXT1 color block
        c0 = struct.unpack("<H", block[8:10])[0]
        c1 = struct.unpack("<H", block[10:12])[0]

        colors = [
            self._rgb565_to_rgba(c0),
            self._rgb565_to_rgba(c1),
            self._interpolate_color(self._rgb565_to_rgba(c0),
                                   self._rgb565_to_rgba(c1), 1, 3),
            self._interpolate_color(self._rgb565_to_rgba(c0),
                                   self._rgb565_to_rgba(c1), 2, 3),
        ]

        color_indices = struct.unpack("<I", block[12:16])[0]

        for y in range(4):
            for x in range(4):
                px, py = start_x + x, start_y + y
                if px < width and py < height:
                    color_idx = (color_indices >> ((y * 4 + x) * 2)) & 0x3
                    alpha_idx = (alpha_indices >> ((y * 4 + x) * 3)) & 0x7

                    r, g, b, _ = colors[color_idx]
                    a = alphas[alpha_idx]

                    offset = (py * width + px) * 4
                    result[offset:offset + 4] = bytes((r, g, b, a))


def main():
    """CLI for TEX extraction."""
    import argparse

    parser = argparse.ArgumentParser(description="Extract WildStar TEX textures")
    parser.add_argument("input", help="Input .tex file or directory")
    parser.add_argument("-o", "--output", default="./output", help="Output directory")
    parser.add_argument("--format", choices=["png", "dds"], default="png",
                       help="Output format (default: png)")
    parser.add_argument("--info", action="store_true", help="Print texture info only")

    args = parser.parse_args()

    input_path = Path(args.input)
    if input_path.is_file():
        files = [input_path]
    else:
        files = list(input_path.glob("**/*.tex"))

    if not files:
        print("No .tex files found")
        return

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    for tex_file in files:
        extractor = TexExtractor(str(tex_file))

        if args.info:
            info = extractor.get_info()
            print(f"{tex_file.name}: {info['width']}x{info['height']} {info['format']} ({info['mip_count']} mips)")
            continue

        output_file = output_dir / f"{tex_file.stem}.{args.format}"

        if args.format == "png":
            success = extractor.to_png(str(output_file))
        else:
            success = extractor.to_dds(str(output_file))

        if success:
            print(f"Exported: {output_file}")
        else:
            print(f"Failed: {tex_file}")


if __name__ == "__main__":
    main()
