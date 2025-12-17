"""glTF exporter for M3 model files."""
import struct
from typing import BinaryIO, List, Tuple, Union
from pathlib import Path

from pygltflib import (
    GLTF2,
    Buffer,
    BufferView,
    Accessor,
    Mesh,
    Primitive,
    Node,
    Scene,
    Asset,
)

from m3_parser import M3Parser
from m3_types import M3Chunk


class GLTFExporter:
    """Exports M3 model data to glTF/GLB format."""

    def __init__(self, source: Union[str, Path, BinaryIO]):
        """Initialize exporter with M3 file path or file-like object.

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

    def _get_vertices(self, file: BinaryIO, chunks: List[M3Chunk]) -> List[Tuple[float, float, float]]:
        """Extract vertex positions from VPOS chunk."""
        vpos_chunk = self._find_chunk(chunks, "VPOS")
        if not vpos_chunk:
            return []

        file.seek(vpos_chunk.offset)
        data = file.read(vpos_chunk.size)

        vertices = []
        vertex_size = 12  # 3 floats * 4 bytes
        for i in range(0, len(data) - vertex_size + 1, vertex_size):
            x, y, z = struct.unpack("<fff", data[i : i + 12])
            vertices.append((x, y, z))

        return vertices

    def _get_indices(self, file: BinaryIO, chunks: List[M3Chunk]) -> List[int]:
        """Extract triangle indices from INDX chunk."""
        indx_chunk = self._find_chunk(chunks, "INDX")
        if not indx_chunk:
            return []

        file.seek(indx_chunk.offset)
        data = file.read(indx_chunk.size)

        indices = []
        for i in range(0, len(data) - 1, 2):
            idx = struct.unpack("<H", data[i : i + 2])[0]
            indices.append(idx)

        return indices

    def _compute_bounds(self, vertices: List[Tuple[float, float, float]]) -> Tuple[List[float], List[float]]:
        """Compute min/max bounds for vertices."""
        if not vertices:
            return [0, 0, 0], [0, 0, 0]

        min_bounds = [float("inf")] * 3
        max_bounds = [float("-inf")] * 3

        for v in vertices:
            for i in range(3):
                min_bounds[i] = min(min_bounds[i], v[i])
                max_bounds[i] = max(max_bounds[i], v[i])

        return min_bounds, max_bounds

    def export(self, output_path: str, include_skeleton: bool = False, include_animations: bool = False):
        """Export M3 data to glTF/GLB file.

        Args:
            output_path: Path for output .glb file
            include_skeleton: Whether to include skeleton/bones
            include_animations: Whether to include animations

        Raises:
            ValueError: If no mesh data found in M3 file
        """
        file = self._get_file()
        try:
            chunks = self._load_chunks(file)
            vertices = self._get_vertices(file, chunks)
            indices = self._get_indices(file, chunks)

            if not vertices or not indices:
                raise ValueError("No mesh data found in M3 file")

            gltf = GLTF2()
            gltf.asset = Asset(version="2.0", generator="M3 Extractor")

            # Pack vertex data (position only for now)
            vertex_data = b""
            for v in vertices:
                vertex_data += struct.pack("<fff", *v)

            # Pack index data
            index_data = b""
            for i in indices:
                index_data += struct.pack("<H", i)

            # Pad index data to 4-byte alignment if needed
            if len(index_data) % 4 != 0:
                index_data += b"\x00" * (4 - len(index_data) % 4)

            # Create combined buffer
            buffer_data = vertex_data + index_data
            gltf.buffers = [Buffer(byteLength=len(buffer_data))]

            # Create buffer views
            gltf.bufferViews = [
                BufferView(
                    buffer=0,
                    byteOffset=0,
                    byteLength=len(vertex_data),
                    target=34962,  # ARRAY_BUFFER
                ),
                BufferView(
                    buffer=0,
                    byteOffset=len(vertex_data),
                    byteLength=len(index_data),
                    target=34963,  # ELEMENT_ARRAY_BUFFER
                ),
            ]

            # Compute bounds for position accessor
            min_bounds, max_bounds = self._compute_bounds(vertices)

            # Create accessors
            gltf.accessors = [
                Accessor(
                    bufferView=0,
                    componentType=5126,  # FLOAT
                    count=len(vertices),
                    type="VEC3",
                    max=max_bounds,
                    min=min_bounds,
                ),
                Accessor(
                    bufferView=1,
                    componentType=5123,  # UNSIGNED_SHORT
                    count=len(indices),
                    type="SCALAR",
                ),
            ]

            # Create mesh with primitive
            gltf.meshes = [
                Mesh(
                    primitives=[
                        Primitive(
                            attributes={"POSITION": 0},
                            indices=1,
                            mode=4,  # TRIANGLES
                        )
                    ]
                )
            ]

            # Create node and scene
            gltf.nodes = [Node(mesh=0, name="mesh_0")]
            gltf.scenes = [Scene(nodes=[0])]
            gltf.scene = 0

            # Set binary data and save
            gltf.set_binary_blob(buffer_data)
            gltf.save(output_path)

        finally:
            if isinstance(self.source, (str, Path)):
                file.close()
