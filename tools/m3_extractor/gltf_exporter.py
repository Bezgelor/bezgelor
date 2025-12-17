"""glTF exporter for WildStar M3 model files."""
import struct
from typing import List, Optional, Tuple, Union
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
    Skin,
)

from m3_mesh import M3MeshExtractor
from m3_skeleton import M3SkeletonExtractor, Skeleton, Bone


class GLTFExporter:
    """Exports WildStar M3 model data to glTF/GLB format."""

    def __init__(self, source: Union[str, Path]):
        """Initialize exporter with M3 file path.

        Args:
            source: Path to M3 file
        """
        self.source = source
        self.mesh_extractor = M3MeshExtractor(source)
        self.skeleton_extractor = M3SkeletonExtractor(source)

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

    def _build_skeleton_nodes(
        self, skeleton: Skeleton, base_node_index: int
    ) -> Tuple[List[Node], List[int], bytes]:
        """Build glTF nodes for skeleton bones.

        Args:
            skeleton: Skeleton with bones
            base_node_index: Starting index for bone nodes (after mesh nodes)

        Returns:
            Tuple of (bone nodes, joint indices, inverse bind matrices buffer)
        """
        nodes = []
        joint_indices = []
        ibm_data = b""

        for bone in skeleton.bones:
            # Node index for this bone
            node_idx = base_node_index + bone.index
            joint_indices.append(node_idx)

            # Find children
            children = [
                base_node_index + child.index
                for child in skeleton.get_children(bone)
            ]

            # Create node with position (translation)
            # The transform matrix is stored as column-major 4x4
            # For simplicity, we'll use the position and let Three.js handle it
            node = Node(
                name=f"bone_{bone.index}",
                translation=list(bone.position),
                children=children if children else None,
            )
            nodes.append(node)

            # Pack inverse bind matrix (column-major, 16 floats)
            for val in bone.inverse_matrix:
                ibm_data += struct.pack("<f", val)

        return nodes, joint_indices, ibm_data

    def export(self, output_path: str, include_skeleton: bool = False, include_animations: bool = False):
        """Export M3 data to glTF/GLB file.

        Args:
            output_path: Path for output .glb file
            include_skeleton: Whether to include skeleton/bones
            include_animations: Whether to include animations (not yet implemented)

        Raises:
            ValueError: If no mesh data found in M3 file
        """
        # Extract mesh data using the mesh extractor
        vertices = self.mesh_extractor.get_vertices()
        uvs = self.mesh_extractor.get_uvs()
        indices = self.mesh_extractor.get_indices()

        if not vertices or not indices:
            raise ValueError("No mesh data found in M3 file")

        # Extract skeleton if requested
        skeleton = None
        if include_skeleton:
            skeleton = self.skeleton_extractor.get_skeleton()
            if skeleton.bone_count == 0:
                skeleton = None  # No bones found

        gltf = GLTF2()
        gltf.asset = Asset(version="2.0", generator="WildStar M3 Extractor")

        # Pack vertex data (position only for now)
        # WildStar vertices are normalized to -1..1 range
        vertex_data = b""
        for v in vertices:
            vertex_data += struct.pack("<fff", *v)

        # Pack UV data
        uv_data = b""
        for uv in uvs:
            # Flip V coordinate for glTF (1.0 - v)
            uv_data += struct.pack("<ff", uv[0], 1.0 - uv[1])

        # Pack index data
        index_data = b""
        for i in indices:
            index_data += struct.pack("<H", i)

        # Pad index data to 4-byte alignment if needed
        if len(index_data) % 4 != 0:
            index_data += b"\x00" * (4 - len(index_data) % 4)

        # Build skeleton data if included
        ibm_data = b""
        bone_nodes = []
        joint_indices = []
        if skeleton:
            bone_nodes, joint_indices, ibm_data = self._build_skeleton_nodes(
                skeleton, base_node_index=1  # Node 0 is the mesh
            )

        # Create combined buffer
        buffer_data = vertex_data + uv_data + index_data + ibm_data
        gltf.buffers = [Buffer(byteLength=len(buffer_data))]

        # Create buffer views
        uv_offset = len(vertex_data)
        index_offset = uv_offset + len(uv_data)
        ibm_offset = index_offset + len(index_data)

        gltf.bufferViews = [
            # Vertex positions
            BufferView(
                buffer=0,
                byteOffset=0,
                byteLength=len(vertex_data),
                target=34962,  # ARRAY_BUFFER
            ),
            # UV coordinates
            BufferView(
                buffer=0,
                byteOffset=uv_offset,
                byteLength=len(uv_data),
                target=34962,  # ARRAY_BUFFER
            ),
            # Indices
            BufferView(
                buffer=0,
                byteOffset=index_offset,
                byteLength=len(index_data),
                target=34963,  # ELEMENT_ARRAY_BUFFER
            ),
        ]

        # Add inverse bind matrix buffer view if we have skeleton
        if skeleton:
            gltf.bufferViews.append(
                BufferView(
                    buffer=0,
                    byteOffset=ibm_offset,
                    byteLength=len(ibm_data),
                )
            )

        # Compute bounds for position accessor
        min_bounds, max_bounds = self._compute_bounds(vertices)

        # Create accessors
        gltf.accessors = [
            # Positions
            Accessor(
                bufferView=0,
                componentType=5126,  # FLOAT
                count=len(vertices),
                type="VEC3",
                max=max_bounds,
                min=min_bounds,
            ),
            # UVs
            Accessor(
                bufferView=1,
                componentType=5126,  # FLOAT
                count=len(uvs),
                type="VEC2",
            ),
            # Indices
            Accessor(
                bufferView=2,
                componentType=5123,  # UNSIGNED_SHORT
                count=len(indices),
                type="SCALAR",
            ),
        ]

        # Add inverse bind matrices accessor if we have skeleton
        ibm_accessor_index = None
        if skeleton:
            ibm_accessor_index = len(gltf.accessors)
            gltf.accessors.append(
                Accessor(
                    bufferView=3,  # IBM buffer view
                    componentType=5126,  # FLOAT
                    count=skeleton.bone_count,
                    type="MAT4",
                )
            )

        # Create mesh with primitive
        gltf.meshes = [
            Mesh(
                primitives=[
                    Primitive(
                        attributes={
                            "POSITION": 0,
                            "TEXCOORD_0": 1,
                        },
                        indices=2,
                        mode=4,  # TRIANGLES
                    )
                ]
            )
        ]

        # Build nodes
        mesh_node = Node(mesh=0, name="mesh_0")
        if skeleton:
            # Link mesh to skin
            mesh_node.skin = 0

        gltf.nodes = [mesh_node]

        # Add bone nodes if we have skeleton
        if skeleton:
            gltf.nodes.extend(bone_nodes)

            # Find root bone node indices
            root_bone_indices = [
                1 + bone.index for bone in skeleton.root_bones
            ]

            # Create skin
            gltf.skins = [
                Skin(
                    joints=joint_indices,
                    inverseBindMatrices=ibm_accessor_index,
                    skeleton=root_bone_indices[0] if root_bone_indices else None,
                    name="skeleton",
                )
            ]

            # Scene includes mesh and root bones
            gltf.scenes = [Scene(nodes=[0] + root_bone_indices)]
        else:
            gltf.scenes = [Scene(nodes=[0])]

        gltf.scene = 0

        # Set binary data and save
        gltf.set_binary_blob(buffer_data)
        gltf.save(output_path)
