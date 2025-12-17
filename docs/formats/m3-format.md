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

## Skeleton / Bone Data

Based on [NexusVault-Java](https://github.com/MarbleBag/NexusVault-Java) research:

### Header Bone Pointer (at offset 0x180)

```c
struct BonePointer {
    int64_t count;      // Number of bones
    int64_t offset;     // Offset from header end (1584) to bone data
};
```

### Bone Structure (0x160 = 352 bytes per bone)

```c
struct Bone {
    int16_t gap_000;        // 0x000: Bind value (often 65535/-1)
    uint16_t gap_002;       // 0x002: Unknown
    int16_t parentId;       // 0x004: Parent bone index (-1 for root)
    uint8_t gap_006[2];     // 0x006: Grouping index
    uint32_t gap_008;       // 0x008: Bone binding value
    int32_t padding_00C;    // 0x00C: Padding

    // Pointer structures 0x010-0x0CF (animation data, etc.)

    float matrix_0D0[16];   // 0x0D0: 4x4 transformation matrix (column-major)
    float matrix_110[16];   // 0x110: 4x4 inverse bind matrix (column-major)

    float x;                // 0x150: Position X
    float y;                // 0x154: Position Y
    float z;                // 0x158: Position Z
    int32_t padding_15C;    // 0x15C: Padding
};
```

### Bone Hierarchy

- Root bones have `parentId = -1`
- Child bones reference their parent by index
- WildStar character models typically have 100-200 bones
- Maximum hierarchy depth observed: 14 levels (for finger/facial bones)

### Example: Aurin Female Character

- Total bones: 173
- Root bones: 1
- Max depth: 14

## References

- [NexusVault-Java](https://github.com/MarbleBag/NexusVault-Java) - Most complete M3 parsing implementation
- [Wildstar M3 Model Load/Export Gist](https://gist.github.com/akderebur/adda1c91197d21b87350f0860ad817af)
- [WoWDev M3 Documentation](https://wowdev.wiki/M3)
- [OwnedCore Wildstar Studio Thread](https://www.ownedcore.com/forums/mmo/wildstar/wildstar-bots-programs/448310-wildstar-studio-file-viewer-explorer.html)

## Notes

- The format evolved across WildStar versions
- Some tools report .m3 files work for geometry but not animations
- Actual structure may vary - verify against real files during implementation
