# WildStar M3 Model Format

Documentation for the WildStar .m3 3D model file format, reverse-engineered from various sources.

## Overview

M3 files are chunked binary files containing 3D model data including:
- Vertex positions, normals, and UVs
- Triangle indices
- Bone/skeleton data
- Material references
- Collision meshes

## File Structure

### Magic and Header

The file begins with magic bytes and a header:

| Offset | Size | Description |
|--------|------|-------------|
| 0x000 | 4 | Magic bytes: `LDOM` (little-endian, = 0x4D4F444C) |
| 0x004 | 4 | Version |
| 0x008 | varies | Header data (version-dependent) |

Some versions use a 376-byte M3DT header, others extend to ~1584 bytes.

### Chunk Format

After the header, data is organized in chunks with 16-byte headers:

```c
struct ChunkHeader {
    uint32_t chunkID;      // 4-char ASCII identifier
    uint32_t chunkSize;    // Size of data (excludes header)
    uint32_t propertyA;    // Chunk-specific metadata
    uint32_t propertyB;    // Chunk-specific metadata
};
```

### Known Chunk Types

| Chunk ID | Purpose |
|----------|---------|
| `M3DT` | Primary header with bounding box, flags |
| `M3VR` | Mesh version |
| `MES3` | Mesh data container |
| `VPOS` | Vertex positions |
| `VNML` | Vertex normals (compressed to 3 bytes + padding) |
| `VWTS` | Vertex bone weights |
| `M3CL` | Collision mesh container |
| `CPOS` | Collision vertex positions |
| `CNML` | Collision normals |
| `CINX` | Collision indices |
| `M3SI` | Material instances |
| `M3ST` | String table |
| `M3PT` | Particle data |

### M3DT Header Structure (376 bytes)

```c
struct M3DT {
    uint32_t version;
    uint32_t propertyB;
    uint32_t unknown[6];      // 0x08-0x1C
    uint32_t flags;           // 0x20
    CAaBox boundingBox;       // 0x24 (24 bytes)
    float radius;             // 0x3C
    CAaBox boundingBox2;      // 0x40 (24 bytes)
    float radius2;            // 0x58
    uint8_t particleCount;    // 0x5C
    uint8_t padding[3];       // 0x5D-0x5F
    // ... additional fields
};
```

### Vertex Data

Vertices are stored in `VPOS` chunks:
- Positions: Often stored as `int16` normalized by `32767.0`
- Normals: Compressed to 3 bytes (values -1 to 1), with 1 byte padding for alignment
- UVs: Half-precision floats (2 bytes each)

Format specifiers found in data:
- `1F32` - 1 float32
- `3F32` - 3 float32s (typical position)
- `4U8N` - 4 normalized uint8s
- `U10N` - 10-bit unsigned normalized

### Index Data

Triangle indices stored as `uint16` values in the index buffer section.

### Mesh Table

Located at an offset specified in the header (around byte 600):
- Vertex count (int32)
- Bytes per vertex (int16)
- Index count (int32)
- Index buffer offset (int64)
- Submesh count (int64)
- Submesh table offset (int64)

### Submesh Entries (112 bytes each)

```c
struct Submesh {
    int32_t startIndex;
    int32_t startVertex;
    int32_t indexCount;
    int32_t vertexCount;
    // ... additional fields
};
```

## References

- [Wildstar M3 Model Load/Export Gist](https://gist.github.com/akderebur/adda1c91197d21b87350f0860ad817af)
- [WoWDev M3 Documentation](https://wowdev.wiki/M3)
- [OwnedCore Wildstar Studio Thread](https://www.ownedcore.com/forums/mmo/wildstar/wildstar-bots-programs/448310-wildstar-studio-file-viewer-explorer.html)

## Notes

- The format evolved across WildStar versions
- Some tools report .m3 files work for geometry but not animations
- Actual structure may vary - verify against real files during implementation
