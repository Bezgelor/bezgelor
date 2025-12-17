# WildStar TEX Type-3 Format Research

## Overview

WildStar uses `type=3` for ~100% of textures in the final game version. This differs from the documented `type=0` standard format.

## Type-3 Sub-formats

### Simple Type-3 (DXT with count=0)

Used for: UI textures, smaller assets

**Structure:**
```
32 bytes: Standard TEX header
80 bytes: Secondary header (mostly zeros)
N bytes:  Standard DXT1/DXT3/DXT5 data
```

**Characteristics:**
- `type=3` in header
- `format=13/14/15` (DXT1/DXT3/DXT5)
- First 4 bytes after TEX header are `0x00000000` (count=0)
- No mipmaps (mip_count=1)
- Data at offset 80 is standard DXT block data

**Status:** ✅ Fully supported in tex_extractor.py

### Complex Type-3 (Custom Compression)

Used for: Character textures, large environment textures

**Structure:**
```
32 bytes: Standard TEX header

Secondary Header:
  4 bytes: count (>0)
  4 bytes: padding (zeros)
  16 bytes: 4 RGB colors (palette?)
  44 bytes: 11 mipmap offsets (relative to secondary header start)

Variable: Compressed texture data
```

**Observed format distribution:**
- format=0 (61%): Custom block format, possibly BC7 variant
- format=13 (18%): DXT1 with streaming compression
- format=15 (8%): DXT5 with streaming compression
- format=6 (8%): Unknown
- format=1 (5%): Unknown

**Compression Analysis:**

For a 1024x1024 texture with 11 mipmaps:
- Expected BC7 size: ~1.4 MB
- Actual file data: ~151 KB
- Compression ratio: ~9:1

The extreme compression ratio suggests:
1. LZ4/Deflate/Crunch on top of block compression, OR
2. Palette-based encoding using the 4 RGB colors in header, OR
3. Custom streaming format optimized for GPU decompression

**Not LZ4 or zlib:** Tested decompression failed with both.

**Status:** ❌ Not yet supported

## Recommendations

For the 3D character viewer:

1. **Short-term:** Use placeholder textures for type-3 complex textures
2. **Medium-term:** Pre-extract textures using external tools if available
3. **Long-term:** Reverse engineer the complex format using:
   - NexusForever client memory dumps during texture loading
   - GPU debugger captures to see final decompressed data
   - Comparison with known BC7 implementations

## References

- [WildStar Wiki: TEX file](https://wildstaronline-archive.fandom.com/wiki/TEX_file)
- [BC7 Format - Microsoft](https://learn.microsoft.com/en-us/windows/win32/direct3d11/bc7-format)
- [NexusForever](https://github.com/NexusForever/NexusForever)
