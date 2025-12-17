# WildStar TEX Texture Format

WildStar uses a proprietary .tex texture format for storing game textures.

## Header Structure (32 bytes)

| Offset | Size | Field       | Description                              |
|--------|------|-------------|------------------------------------------|
| 0x00   | 4    | magic       | "XFG\0" (0x58464700)                    |
| 0x04   | 4    | type        | Texture type (0=standard, 3=custom)      |
| 0x08   | 4    | width       | Width in pixels (power of 2)             |
| 0x0C   | 4    | height      | Height in pixels (power of 2)            |
| 0x10   | 4    | depth       | Depth (typically 1)                      |
| 0x14   | 4    | sides       | Sides (1=2D, 6=cubemap)                  |
| 0x18   | 4    | mip_count   | Number of mipmap levels                  |
| 0x1C   | 4    | format      | Compression format                       |

## Type Values

- **Type 0**: Standard DXT-compressed textures
- **Type 3**: Custom block compression (BC7-like, most common in client data)

## Format Values (for Type 0)

| Value | Format              | Description                           |
|-------|---------------------|---------------------------------------|
| 0     | UNCOMPRESSED_RGBA   | 32-bit BGRA, 8 bits per channel       |
| 1     | UNCOMPRESSED_RGB    | 24-bit BGR                            |
| 13    | DXT1                | 4-bit color, 1-bit alpha              |
| 14    | DXT3                | 4-bit color, 4-bit explicit alpha     |
| 15    | DXT5                | 4-bit color, interpolated alpha       |

## Mipmap Storage

Mipmaps are stored **smallest to largest** (opposite of DDS format):
- First mipmap (level 0) is the smallest pre-rendered image
- Each subsequent level doubles both dimensions
- Final mipmap is the full-size image matching header dimensions

## Type 3 Textures

Most WildStar textures use **type 3** with a custom block compression format:
- Format field is typically 0 but does NOT mean uncompressed
- Appears to use BC7-like compression with palette lookup
- Extended header may follow the 32-byte base header
- Data at offset 0x28+ contains what appears to be color palette entries

### Known Type 3 Patterns

After the header, type 3 textures have additional data before pixel data:
- Bytes 0x20-0x27: Unknown fields (possibly layer count, flags)
- Bytes 0x28+: May contain color palette or mipmap offset table

## Tools

The `tex_extractor.py` tool can:
- Parse and display TEX file information
- Export type 0 textures with DXT1/3/5 compression to PNG or DDS
- Export raw data for type 3 textures (requires external BC7 decoder)

## References

- [WildStar TEX file - Fandom Wiki](https://wildstaronline-archive.fandom.com/wiki/TEX_file)
- [WildStar TEX file - AddOn Studio](https://addonstudio.org/wiki/WildStar:TEX_file)

## Status

- Type 0 with DXT1/3/5: **Supported**
- Type 0 uncompressed: **Supported**
- Type 3 (custom compression): **Not yet supported** - requires further research
