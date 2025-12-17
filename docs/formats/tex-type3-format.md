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

**WildStar Studio Analysis:**
- Examined source code from https://bitbucket.org/mugadr_m/wildstar-studio
- The Texture.cpp only handles sequential mipmap reading after a 32-byte header
- Does NOT handle the 68+ byte secondary header for complex type-3
- Uses zlib for archive-level decompression (not texture-level)
- Conclusion: This tool doesn't implement the complex type-3 decoder

**Status:** ❌ Not yet supported

## Extraction Strategy

### Supported by tex_extractor.py

1. **Simple Type-3 (DXT, count=0)**: ✅ Full PNG/DDS export
2. **Type-0 Standard textures**: ✅ Full support (if any exist)

### Requires External Tool

For complex type-3 textures (character skins, etc.), use WildStar Studio:

1. Download WildStar Studio from the [OwnedCore release thread](https://www.ownedcore.com/forums/mmo/wildstar/wildstar-bots-programs/448310-wildstar-studio-file-viewer-explorer.html)
2. Open the game archive (.index file)
3. Navigate to texture directories (Art\Character\*, Art\Creature\*, etc.)
4. Select textures and use "Export as PNG" or "Export as BMP"
5. Place exported files in `priv/static/textures/` for web viewer

**Note:** The compiled WildStar Studio binary can decode all textures despite
the source code not showing the complex type-3 algorithm. This suggests either
additional binary-only code or archive-level preprocessing.

### Batch Extraction Script

For batch extraction of character textures, create a list of required paths
from the game data and extract manually via the GUI, OR use automation tools
like AutoHotkey with WildStar Studio.

### Fallback Approach

For the 3D character viewer, if textures are unavailable:
1. Use solid color placeholder materials based on armor type
2. Generate procedural textures from item quality colors
3. Display "texture not available" indicator

## Technical Notes

The complex type-3 compression appears to be:
- NOT standard zlib, LZ4, or zstd
- Possibly a custom streaming format for GPU decompression
- May use the 4 RGB values in the secondary header as a base palette
- Achieves ~18:1 compression beyond BC7 (unusual for texture compression)

Further reverse engineering would require:
- Memory dumps during WildStar client texture loading
- GPU debugger captures (RenderDoc, etc.) to see decompressed data
- Analysis of the compiled WildStar Studio binary (if legal to reverse engineer)

## References

- [WildStar Wiki: TEX file](https://wildstaronline-archive.fandom.com/wiki/TEX_file)
- [AddOn Studio: TEX format](https://addonstudio.org/wiki/WildStar:TEX_file)
- [WildStar Studio Release](https://www.ownedcore.com/forums/mmo/wildstar/wildstar-bots-programs/448310-wildstar-studio-file-viewer-explorer.html)
- [BC7 Format - Microsoft](https://learn.microsoft.com/en-us/windows/win32/direct3d11/bc7-format)
- [NexusForever](https://github.com/NexusForever/NexusForever)
