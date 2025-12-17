# Portal Admin & 3D Character Viewer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add admin item search/management, user bank tab, and 3D WebGL character viewer using extracted WildStar M3 models.

**Architecture:** Four phases: (1) M3 model extraction Python tooling, (2) Three.js browser integration, (3) Admin item management features, (4) User character sheet enhancements. Phases 3-4 can run parallel to Phase 1.

**Tech Stack:** Python 3.11+ (struct, pygltflib), Three.js + GLTFLoader, Phoenix LiveView, ETS data store

---

## Phase 1: M3 Model Extraction Tool

### Task 1: Research M3 Format & Create Project Structure

**Files:**
- Create: `tools/m3_extractor/README.md`
- Create: `tools/m3_extractor/requirements.txt`
- Create: `docs/formats/m3-format.md`

**Step 1: Create project structure**

```bash
mkdir -p tools/m3_extractor/tests
mkdir -p docs/formats
```

**Step 2: Create requirements.txt**

```
# tools/m3_extractor/requirements.txt
pygltflib>=1.16.0
numpy>=1.24.0
Pillow>=10.0.0
pytest>=7.0.0
```

**Step 3: Research M3 format from WildStar modding resources**

Search for existing M3 documentation:
- WildStar Modding Discord/forums
- NexusForever source code for model references
- Examine sample .m3 file headers with hexdump

**Step 4: Document initial findings**

Create `docs/formats/m3-format.md` with header structure.

**Step 5: Commit**

```bash
git add tools/m3_extractor docs/formats
git commit -m "feat(tools): scaffold M3 extractor project"
```

---

### Task 2: Parse M3 Header

**Files:**
- Create: `tools/m3_extractor/m3_types.py`
- Create: `tools/m3_extractor/m3_parser.py`
- Test: `tools/m3_extractor/tests/test_m3_parser.py`

**Step 1: Write the failing test**

```python
# tools/m3_extractor/tests/test_m3_parser.py
import pytest
from m3_parser import M3Parser

def test_parse_header_magic():
    """M3 files should start with magic bytes '43MD' or 'MD34'."""
    parser = M3Parser()
    with open("tests/fixtures/sample.m3", "rb") as f:
        header = parser.parse_header(f)

    assert header.magic in [b"43MD", b"MD34"]
    assert header.version > 0

def test_parse_header_invalid_magic():
    """Should raise on invalid magic bytes."""
    parser = M3Parser()
    with pytest.raises(ValueError, match="Invalid M3 magic"):
        parser.parse_header_bytes(b"XXXX" + b"\x00" * 100)
```

**Step 2: Run test to verify it fails**

```bash
cd tools/m3_extractor
python -m pytest tests/test_m3_parser.py -v
```

Expected: FAIL with "ModuleNotFoundError: No module named 'm3_parser'"

**Step 3: Create m3_types.py**

```python
# tools/m3_extractor/m3_types.py
from dataclasses import dataclass
from typing import List

@dataclass
class M3Header:
    magic: bytes
    version: int
    index_offset: int
    index_count: int

@dataclass
class M3Chunk:
    id: str
    offset: int
    size: int
    data: bytes = None
```

**Step 4: Write minimal m3_parser.py**

```python
# tools/m3_extractor/m3_parser.py
import struct
from m3_types import M3Header, M3Chunk

class M3Parser:
    VALID_MAGIC = [b"43MD", b"MD34"]

    def parse_header(self, file) -> M3Header:
        data = file.read(16)
        return self.parse_header_bytes(data)

    def parse_header_bytes(self, data: bytes) -> M3Header:
        magic = data[:4]
        if magic not in self.VALID_MAGIC:
            raise ValueError(f"Invalid M3 magic: {magic}")

        version, index_offset, index_count = struct.unpack("<III", data[4:16])
        return M3Header(magic=magic, version=version,
                        index_offset=index_offset, index_count=index_count)
```

**Step 5: Run test to verify it passes**

```bash
python -m pytest tests/test_m3_parser.py::test_parse_header_invalid_magic -v
```

Expected: PASS

**Step 6: Commit**

```bash
git add tools/m3_extractor/
git commit -m "feat(m3): add M3 header parser with magic validation"
```

---

### Task 3: Parse M3 Chunk Index

**Files:**
- Modify: `tools/m3_extractor/m3_parser.py`
- Test: `tools/m3_extractor/tests/test_m3_parser.py`

**Step 1: Write the failing test**

```python
# Add to tests/test_m3_parser.py
def test_parse_chunks():
    """Should parse chunk index from M3 file."""
    parser = M3Parser()
    with open("tests/fixtures/sample.m3", "rb") as f:
        chunks = parser.parse_chunks(f)

    assert len(chunks) > 0
    assert all(isinstance(c, M3Chunk) for c in chunks)
    # M3 files typically have MODL, VERT, INDX, BONE chunks
    chunk_ids = [c.id for c in chunks]
    assert "MODL" in chunk_ids or "VERT" in chunk_ids
```

**Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_m3_parser.py::test_parse_chunks -v
```

Expected: FAIL with "AttributeError: 'M3Parser' object has no attribute 'parse_chunks'"

**Step 3: Implement parse_chunks**

```python
# Add to m3_parser.py
def parse_chunks(self, file) -> List[M3Chunk]:
    header = self.parse_header(file)
    file.seek(header.index_offset)

    chunks = []
    for _ in range(header.index_count):
        chunk_data = file.read(16)
        chunk_id = chunk_data[:4].decode('ascii', errors='replace')
        offset, size, _ = struct.unpack("<III", chunk_data[4:16])
        chunks.append(M3Chunk(id=chunk_id, offset=offset, size=size))

    return chunks
```

**Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_m3_parser.py::test_parse_chunks -v
```

**Step 5: Commit**

```bash
git commit -am "feat(m3): add chunk index parsing"
```

---

### Task 4: Extract Vertex Data

**Files:**
- Modify: `tools/m3_extractor/m3_parser.py`
- Create: `tools/m3_extractor/m3_mesh.py`
- Test: `tools/m3_extractor/tests/test_m3_mesh.py`

**Step 1: Write the failing test**

```python
# tools/m3_extractor/tests/test_m3_mesh.py
import pytest
from m3_mesh import M3MeshExtractor

def test_extract_vertices():
    """Should extract vertex positions from VERT chunk."""
    extractor = M3MeshExtractor("tests/fixtures/sample.m3")
    vertices = extractor.get_vertices()

    assert len(vertices) > 0
    assert all(len(v) == 3 for v in vertices)  # x, y, z
    # Vertices should be reasonable floats
    for v in vertices[:10]:
        assert all(-10000 < coord < 10000 for coord in v)
```

**Step 2: Run test to verify it fails**

```bash
python -m pytest tests/test_m3_mesh.py -v
```

**Step 3: Implement M3MeshExtractor**

```python
# tools/m3_extractor/m3_mesh.py
import struct
from typing import List, Tuple
from m3_parser import M3Parser

class M3MeshExtractor:
    def __init__(self, filepath: str):
        self.filepath = filepath
        self.parser = M3Parser()
        self._chunks = None

    def get_vertices(self) -> List[Tuple[float, float, float]]:
        with open(self.filepath, "rb") as f:
            chunks = self.parser.parse_chunks(f)

            # Find VERT chunk
            vert_chunk = next((c for c in chunks if c.id == "VERT"), None)
            if not vert_chunk:
                return []

            f.seek(vert_chunk.offset)
            data = f.read(vert_chunk.size)

            # Parse vertices (assuming 32 bytes per vertex: pos + normal + uv)
            vertices = []
            vertex_size = 32
            for i in range(0, len(data) - vertex_size + 1, vertex_size):
                x, y, z = struct.unpack("<fff", data[i:i+12])
                vertices.append((x, y, z))

            return vertices
```

**Step 4: Run test to verify it passes**

```bash
python -m pytest tests/test_m3_mesh.py -v
```

**Step 5: Commit**

```bash
git add tools/m3_extractor/
git commit -m "feat(m3): add vertex extraction from VERT chunks"
```

---

### Task 5: Extract Index Buffers

**Files:**
- Modify: `tools/m3_extractor/m3_mesh.py`
- Test: `tools/m3_extractor/tests/test_m3_mesh.py`

**Step 1: Write the failing test**

```python
# Add to tests/test_m3_mesh.py
def test_extract_indices():
    """Should extract triangle indices from INDX chunk."""
    extractor = M3MeshExtractor("tests/fixtures/sample.m3")
    indices = extractor.get_indices()

    assert len(indices) > 0
    assert len(indices) % 3 == 0  # Triangles
    # Indices should reference valid vertices
    vertices = extractor.get_vertices()
    assert all(0 <= i < len(vertices) for i in indices)
```

**Step 2: Run test to verify it fails**

**Step 3: Implement get_indices**

```python
# Add to m3_mesh.py
def get_indices(self) -> List[int]:
    with open(self.filepath, "rb") as f:
        chunks = self.parser.parse_chunks(f)

        indx_chunk = next((c for c in chunks if c.id == "INDX"), None)
        if not indx_chunk:
            return []

        f.seek(indx_chunk.offset)
        data = f.read(indx_chunk.size)

        # Parse as uint16 indices
        indices = []
        for i in range(0, len(data) - 1, 2):
            idx = struct.unpack("<H", data[i:i+2])[0]
            indices.append(idx)

        return indices
```

**Step 4: Run test to verify it passes**

**Step 5: Commit**

```bash
git commit -am "feat(m3): add triangle index extraction"
```

---

### Task 6: Extract Skeleton/Bones

**Files:**
- Modify: `tools/m3_extractor/m3_mesh.py`
- Create: `tools/m3_extractor/m3_skeleton.py`
- Test: `tools/m3_extractor/tests/test_m3_skeleton.py`

**Step 1: Write the failing test**

```python
# tools/m3_extractor/tests/test_m3_skeleton.py
import pytest
from m3_skeleton import M3SkeletonExtractor

def test_extract_bones():
    """Should extract bone hierarchy from BONE chunk."""
    extractor = M3SkeletonExtractor("tests/fixtures/sample.m3")
    bones = extractor.get_bones()

    assert len(bones) > 0
    for bone in bones:
        assert "name" in bone or "id" in bone
        assert "parent_id" in bone
        assert "transform" in bone
```

**Step 2: Run test to verify it fails**

**Step 3: Implement M3SkeletonExtractor**

```python
# tools/m3_extractor/m3_skeleton.py
import struct
from typing import List, Dict
from m3_parser import M3Parser

class M3SkeletonExtractor:
    def __init__(self, filepath: str):
        self.filepath = filepath
        self.parser = M3Parser()

    def get_bones(self) -> List[Dict]:
        with open(self.filepath, "rb") as f:
            chunks = self.parser.parse_chunks(f)

            bone_chunk = next((c for c in chunks if c.id == "BONE"), None)
            if not bone_chunk:
                return []

            f.seek(bone_chunk.offset)
            data = f.read(bone_chunk.size)

            # Parse bone entries (structure TBD based on research)
            bones = []
            bone_size = 64  # Estimated
            for i in range(0, len(data) - bone_size + 1, bone_size):
                bone_id = struct.unpack("<I", data[i:i+4])[0]
                parent_id = struct.unpack("<i", data[i+4:i+8])[0]
                # 4x4 transform matrix
                transform = struct.unpack("<16f", data[i+8:i+72])

                bones.append({
                    "id": bone_id,
                    "parent_id": parent_id,
                    "transform": transform
                })

            return bones
```

**Step 4: Run test to verify it passes**

**Step 5: Commit**

```bash
git add tools/m3_extractor/
git commit -m "feat(m3): add skeleton/bone extraction"
```

---

### Task 7: Extract Animation Data

**Files:**
- Create: `tools/m3_extractor/m3_animation.py`
- Test: `tools/m3_extractor/tests/test_m3_animation.py`

**Step 1: Write the failing test**

```python
# tools/m3_extractor/tests/test_m3_animation.py
import pytest
from m3_animation import M3AnimationExtractor

def test_extract_animations():
    """Should extract animation tracks from ANIM chunk."""
    extractor = M3AnimationExtractor("tests/fixtures/sample.m3")
    animations = extractor.get_animations()

    # Character models should have at least idle animation
    assert len(animations) >= 0  # May be 0 for static models
    for anim in animations:
        assert "name" in anim or "id" in anim
        assert "duration" in anim
        assert "keyframes" in anim
```

**Step 2-5: Implement and verify**

Similar pattern to previous tasks.

**Step 6: Commit**

```bash
git commit -am "feat(m3): add animation data extraction"
```

---

### Task 8: Create glTF Exporter

**Files:**
- Create: `tools/m3_extractor/gltf_exporter.py`
- Test: `tools/m3_extractor/tests/test_gltf_exporter.py`

**Step 1: Write the failing test**

```python
# tools/m3_extractor/tests/test_gltf_exporter.py
import pytest
import os
from gltf_exporter import GLTFExporter

def test_export_basic_mesh():
    """Should export M3 to valid glTF file."""
    exporter = GLTFExporter("tests/fixtures/sample.m3")
    output_path = "tests/output/sample.glb"

    exporter.export(output_path)

    assert os.path.exists(output_path)
    assert os.path.getsize(output_path) > 100

    # Verify it's valid glTF
    from pygltflib import GLTF2
    gltf = GLTF2.load(output_path)
    assert len(gltf.meshes) > 0
```

**Step 2: Run test to verify it fails**

**Step 3: Implement GLTFExporter**

```python
# tools/m3_extractor/gltf_exporter.py
import struct
from pygltflib import GLTF2, Buffer, BufferView, Accessor, Mesh, Primitive, Node, Scene
from m3_mesh import M3MeshExtractor
from m3_skeleton import M3SkeletonExtractor

class GLTFExporter:
    def __init__(self, m3_path: str):
        self.m3_path = m3_path
        self.mesh_extractor = M3MeshExtractor(m3_path)
        self.skeleton_extractor = M3SkeletonExtractor(m3_path)

    def export(self, output_path: str):
        vertices = self.mesh_extractor.get_vertices()
        indices = self.mesh_extractor.get_indices()

        if not vertices or not indices:
            raise ValueError("No mesh data found in M3 file")

        gltf = GLTF2()

        # Pack vertex data
        vertex_data = b""
        for v in vertices:
            vertex_data += struct.pack("<fff", *v)

        # Pack index data
        index_data = b""
        for i in indices:
            index_data += struct.pack("<H", i)

        # Create buffer
        buffer_data = vertex_data + index_data
        gltf.buffers = [Buffer(byteLength=len(buffer_data))]

        # Create buffer views
        gltf.bufferViews = [
            BufferView(buffer=0, byteOffset=0, byteLength=len(vertex_data), target=34962),
            BufferView(buffer=0, byteOffset=len(vertex_data), byteLength=len(index_data), target=34963),
        ]

        # Create accessors
        gltf.accessors = [
            Accessor(bufferView=0, componentType=5126, count=len(vertices), type="VEC3"),
            Accessor(bufferView=1, componentType=5123, count=len(indices), type="SCALAR"),
        ]

        # Create mesh
        gltf.meshes = [Mesh(primitives=[Primitive(attributes={"POSITION": 0}, indices=1)])]
        gltf.nodes = [Node(mesh=0)]
        gltf.scenes = [Scene(nodes=[0])]
        gltf.scene = 0

        # Set binary data and save
        gltf.set_binary_blob(buffer_data)
        gltf.save(output_path)
```

**Step 4: Run test to verify it passes**

**Step 5: Commit**

```bash
git add tools/m3_extractor/
git commit -m "feat(m3): add glTF exporter with mesh support"
```

---

### Task 9: Add Skeleton to glTF Export

**Files:**
- Modify: `tools/m3_extractor/gltf_exporter.py`
- Test: `tools/m3_extractor/tests/test_gltf_exporter.py`

**Step 1: Write the failing test**

```python
def test_export_with_skeleton():
    """Should export M3 with skeleton to glTF."""
    exporter = GLTFExporter("tests/fixtures/character.m3")
    output_path = "tests/output/character.glb"

    exporter.export(output_path, include_skeleton=True)

    from pygltflib import GLTF2
    gltf = GLTF2.load(output_path)
    assert gltf.skins is not None and len(gltf.skins) > 0
```

**Step 2-5: Implement skeleton in glTF, verify**

**Step 6: Commit**

```bash
git commit -am "feat(m3): add skeleton export to glTF"
```

---

### Task 10: Add Animation to glTF Export

**Files:**
- Modify: `tools/m3_extractor/gltf_exporter.py`
- Test: `tools/m3_extractor/tests/test_gltf_exporter.py`

**Step 1: Write the failing test**

```python
def test_export_with_animations():
    """Should export M3 with animations to glTF."""
    exporter = GLTFExporter("tests/fixtures/character.m3")
    output_path = "tests/output/character_animated.glb"

    exporter.export(output_path, include_animations=True)

    from pygltflib import GLTF2
    gltf = GLTF2.load(output_path)
    assert gltf.animations is not None and len(gltf.animations) > 0
```

**Step 2-5: Implement animations in glTF, verify**

**Step 6: Commit**

```bash
git commit -am "feat(m3): add animation export to glTF"
```

---

### Task 11: Create Batch Extraction CLI

**Files:**
- Create: `tools/m3_extractor/extract_models.py`
- Test: `tools/m3_extractor/tests/test_extract_models.py`

**Step 1: Write the failing test**

```python
# tools/m3_extractor/tests/test_extract_models.py
import pytest
import subprocess

def test_cli_help():
    """CLI should show help."""
    result = subprocess.run(["python", "extract_models.py", "--help"],
                          capture_output=True, text=True)
    assert result.returncode == 0
    assert "usage" in result.stdout.lower()

def test_cli_extract_single():
    """CLI should extract a single M3 file."""
    result = subprocess.run([
        "python", "extract_models.py",
        "tests/fixtures/sample.m3",
        "-o", "tests/output/"
    ], capture_output=True, text=True)
    assert result.returncode == 0
```

**Step 2-5: Implement CLI, verify**

```python
# tools/m3_extractor/extract_models.py
import argparse
import os
from pathlib import Path
from gltf_exporter import GLTFExporter

def main():
    parser = argparse.ArgumentParser(description="Extract WildStar M3 models to glTF")
    parser.add_argument("input", help="Input M3 file or directory")
    parser.add_argument("-o", "--output", default="./output", help="Output directory")
    parser.add_argument("--no-skeleton", action="store_true", help="Skip skeleton export")
    parser.add_argument("--no-animation", action="store_true", help="Skip animation export")

    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)

    input_path = Path(args.input)
    if input_path.is_file():
        files = [input_path]
    else:
        files = list(input_path.glob("**/*.m3"))

    for m3_file in files:
        try:
            exporter = GLTFExporter(str(m3_file))
            output_file = Path(args.output) / f"{m3_file.stem}.glb"
            exporter.export(
                str(output_file),
                include_skeleton=not args.no_skeleton,
                include_animations=not args.no_animation
            )
            print(f"Exported: {output_file}")
        except Exception as e:
            print(f"Failed: {m3_file} - {e}")

if __name__ == "__main__":
    main()
```

**Step 6: Commit**

```bash
git add tools/m3_extractor/
git commit -m "feat(m3): add batch extraction CLI"
```

---

## Phase 2: Three.js Integration

### Task 12: Add Three.js Dependencies

**Files:**
- Modify: `apps/bezgelor_portal/assets/package.json`

**Step 1: Add dependencies**

```bash
cd apps/bezgelor_portal/assets
npm install three
```

**Step 2: Verify installation**

```bash
npm ls three
```

Expected: Shows three@0.x.x

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/assets/package.json apps/bezgelor_portal/assets/package-lock.json
git commit -m "feat(portal): add Three.js dependency"
```

---

### Task 13: Create Character Viewer JavaScript Module

**Files:**
- Create: `apps/bezgelor_portal/assets/js/character_viewer.js`

**Step 1: Create the module**

```javascript
// apps/bezgelor_portal/assets/js/character_viewer.js
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

export class CharacterViewer {
  constructor(container, options = {}) {
    this.container = container;
    this.options = {
      width: options.width || 400,
      height: options.height || 500,
      backgroundColor: options.backgroundColor || 0x1a1a2e,
      ...options
    };

    this.scene = null;
    this.camera = null;
    this.renderer = null;
    this.controls = null;
    this.model = null;
    this.mixer = null;
    this.clock = new THREE.Clock();

    this._init();
  }

  _init() {
    // Scene
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(this.options.backgroundColor);

    // Camera
    this.camera = new THREE.PerspectiveCamera(
      45,
      this.options.width / this.options.height,
      0.1,
      1000
    );
    this.camera.position.set(0, 1.5, 3);

    // Renderer
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setSize(this.options.width, this.options.height);
    this.renderer.setPixelRatio(window.devicePixelRatio);
    this.container.appendChild(this.renderer.domElement);

    // Controls
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.set(0, 1, 0);
    this.controls.update();

    // Lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.5);
    this.scene.add(ambientLight);

    const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
    directionalLight.position.set(5, 10, 7.5);
    this.scene.add(directionalLight);

    // Start render loop
    this._animate();
  }

  async loadModel(url) {
    const loader = new GLTFLoader();

    try {
      const gltf = await loader.loadAsync(url);

      // Remove old model
      if (this.model) {
        this.scene.remove(this.model);
      }

      this.model = gltf.scene;
      this.scene.add(this.model);

      // Setup animations if present
      if (gltf.animations && gltf.animations.length > 0) {
        this.mixer = new THREE.AnimationMixer(this.model);
        const idleAnimation = gltf.animations[0];
        const action = this.mixer.clipAction(idleAnimation);
        action.play();
      }

      return true;
    } catch (error) {
      console.error('Failed to load model:', error);
      return false;
    }
  }

  _animate() {
    requestAnimationFrame(() => this._animate());

    const delta = this.clock.getDelta();
    if (this.mixer) {
      this.mixer.update(delta);
    }

    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  dispose() {
    if (this.renderer) {
      this.renderer.dispose();
      this.container.removeChild(this.renderer.domElement);
    }
  }
}
```

**Step 2: Commit**

```bash
git add apps/bezgelor_portal/assets/js/character_viewer.js
git commit -m "feat(portal): add Three.js character viewer module"
```

---

### Task 14: Create LiveView Hook for Character Viewer

**Files:**
- Modify: `apps/bezgelor_portal/assets/js/app.js`
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/hooks.ex`

**Step 1: Create the hook in app.js**

```javascript
// Add to apps/bezgelor_portal/assets/js/app.js
import { CharacterViewer } from './character_viewer';

const CharacterViewerHook = {
  mounted() {
    const race = this.el.dataset.race;
    const gender = this.el.dataset.gender;
    const equipment = JSON.parse(this.el.dataset.equipment || '[]');

    this.viewer = new CharacterViewer(this.el, {
      width: this.el.clientWidth || 400,
      height: 500
    });

    // Load base character model
    const modelUrl = `/models/characters/${race}_${gender}.glb`;
    this.viewer.loadModel(modelUrl).then(success => {
      if (!success) {
        // Show fallback message
        this.el.innerHTML = '<div class="text-center py-12 text-base-content/50">' +
          '<p>Character preview not available</p></div>';
      }
    });
  },

  destroyed() {
    if (this.viewer) {
      this.viewer.dispose();
    }
  }
};

// Add to hooks object
let Hooks = {};
Hooks.CharacterViewer = CharacterViewerHook;

// Update liveSocket
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
});
```

**Step 2: Commit**

```bash
git add apps/bezgelor_portal/assets/js/app.js
git commit -m "feat(portal): add CharacterViewer LiveView hook"
```

---

### Task 15: Create Character Viewer LiveView Component

**Files:**
- Create: `apps/bezgelor_portal/lib/bezgelor_portal_web/components/character_viewer.ex`

**Step 1: Create the component**

```elixir
# apps/bezgelor_portal/lib/bezgelor_portal_web/components/character_viewer.ex
defmodule BezgelorPortalWeb.Components.CharacterViewer do
  @moduledoc """
  3D character viewer component using Three.js.

  Renders character model with equipped gear.
  Falls back to "preview not available" if model missing.
  """
  use Phoenix.Component

  attr :character, :map, required: true
  attr :equipment, :list, default: []
  attr :class, :string, default: ""

  def character_viewer(assigns) do
    ~H"""
    <div
      id={"character-viewer-#{@character.id}"}
      class={"relative bg-base-300 rounded-lg overflow-hidden #{@class}"}
      phx-hook="CharacterViewer"
      data-race={race_key(@character.race_id)}
      data-gender={gender_key(@character.sex)}
      data-equipment={Jason.encode!(@equipment)}
    >
      <div class="absolute inset-0 flex items-center justify-center text-base-content/30">
        <span class="loading loading-spinner loading-lg"></span>
      </div>
    </div>
    """
  end

  defp race_key(1), do: "human"
  defp race_key(2), do: "granok"
  defp race_key(3), do: "aurin"
  defp race_key(4), do: "draken"
  defp race_key(5), do: "mechari"
  defp race_key(6), do: "chua"
  defp race_key(7), do: "mordesh"
  defp race_key(8), do: "cassian"
  defp race_key(_), do: "human"

  defp gender_key(0), do: "male"
  defp gender_key(1), do: "female"
  defp gender_key(_), do: "male"
end
```

**Step 2: Commit**

```bash
git add apps/bezgelor_portal/lib/bezgelor_portal_web/components/character_viewer.ex
git commit -m "feat(portal): add CharacterViewer LiveView component"
```

---

## Phase 3: Admin Item Management

### Task 16: Add Item Search Function to Store

**Files:**
- Modify: `apps/bezgelor_data/lib/bezgelor_data/store.ex`
- Test: `apps/bezgelor_data/test/store_test.exs`

**Step 1: Write the failing test**

```elixir
# Add to apps/bezgelor_data/test/store_test.exs
describe "search_items/1" do
  test "finds items by ID" do
    results = Store.search_items("12345")
    assert is_list(results)
  end

  test "finds items by partial name" do
    results = Store.search_items("sword")
    assert is_list(results)
    # Results should contain items with "sword" in name
  end

  test "returns empty list for no matches" do
    results = Store.search_items("xyznonexistent999")
    assert results == []
  end

  test "limits results to 50" do
    results = Store.search_items("a")  # Common letter
    assert length(results) <= 50
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test apps/bezgelor_data/test/store_test.exs --only search_items
```

**Step 3: Implement search_items**

```elixir
# Add to apps/bezgelor_data/lib/bezgelor_data/store.ex

@doc """
Search items by ID or name.

Returns up to 50 matching items with their localized names.
"""
@spec search_items(String.t()) :: [map()]
def search_items(query) when is_binary(query) do
  query = String.trim(query)

  cond do
    query == "" ->
      []

    # Check if query is a number (item ID)
    match?({_, ""}, Integer.parse(query)) ->
      {id, ""} = Integer.parse(query)
      case get_item(id) do
        {:ok, item} -> [add_item_name(item)]
        :error -> []
      end

    # Search by name
    true ->
      search_items_by_name(query)
  end
end

defp search_items_by_name(query) do
  query_lower = String.downcase(query)

  # Get all items and filter by name
  :ets.tab2list(:items_by_id)
  |> Enum.map(fn {_id, item} -> add_item_name(item) end)
  |> Enum.filter(fn item ->
    name = Map.get(item, :name, "")
    String.contains?(String.downcase(name), query_lower)
  end)
  |> Enum.take(50)
end

defp add_item_name(item) do
  text_id = Map.get(item, :localizedTextIdName, 0)
  name = get_localized_text(text_id) || "Item ##{item.id}"
  Map.put(item, :name, name)
end
```

**Step 4: Run test to verify it passes**

```bash
mix test apps/bezgelor_data/test/store_test.exs --only search_items
```

**Step 5: Commit**

```bash
git add apps/bezgelor_data/
git commit -m "feat(data): add item search by ID or name"
```

---

### Task 17: Create Admin Items LiveView

**Files:**
- Create: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/items_live.ex`
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/router.ex`

**Step 1: Create the LiveView**

```elixir
# apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/items_live.ex
defmodule BezgelorPortalWeb.Admin.ItemsLive do
  @moduledoc """
  Admin page for searching and viewing item data.
  """
  use BezgelorPortalWeb, :live_view

  alias BezgelorData.Store

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Item Database",
       search_query: "",
       search_results: [],
       selected_item: nil
     ),
     layout: {BezgelorPortalWeb.Layouts, :admin}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Item Database</h1>

      <!-- Search -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <form phx-submit="search" phx-change="search_change">
            <div class="join w-full">
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search by item ID or name..."
                class="input input-bordered join-item flex-1"
                phx-debounce="300"
              />
              <button type="submit" class="btn btn-primary join-item">
                <.icon name="hero-magnifying-glass" class="size-5" />
                Search
              </button>
            </div>
          </form>
        </div>
      </div>

      <!-- Results -->
      <div class="card bg-base-100 shadow">
        <div class="card-body">
          <h2 class="card-title">Results ({length(@search_results)})</h2>

          <%= if Enum.empty?(@search_results) do %>
            <p class="text-base-content/50 py-4">
              <%= if @search_query == "" do %>
                Enter a search term to find items.
              <% else %>
                No items found matching "<%= @search_query %>".
              <% end %>
            </p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Name</th>
                    <th>Type</th>
                    <th>Level</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={item <- @search_results} class="hover">
                    <td class="font-mono">{item.id}</td>
                    <td class={item_quality_class(item)}>{item.name}</td>
                    <td>{item_type_name(item)}</td>
                    <td>{Map.get(item, :powerLevel, "-")}</td>
                    <td>
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="view_item"
                        phx-value-id={item.id}
                      >
                        View
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Item Detail Modal -->
      <.item_detail_modal :if={@selected_item} item={@selected_item} />
    </div>
    """
  end

  defp item_detail_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl">
        <h3 class="font-bold text-lg mb-4">{@item.name}</h3>

        <div class="grid grid-cols-2 gap-4 text-sm">
          <div><span class="text-base-content/50">ID:</span> {@item.id}</div>
          <div><span class="text-base-content/50">Type:</span> {item_type_name(@item)}</div>
          <div><span class="text-base-content/50">Power Level:</span> {Map.get(@item, :powerLevel, 0)}</div>
          <div><span class="text-base-content/50">Required Level:</span> {Map.get(@item, :requiredLevel, 0)}</div>
          <div><span class="text-base-content/50">Bind Type:</span> {Map.get(@item, :bindType, 0)}</div>
          <div><span class="text-base-content/50">Max Stack:</span> {Map.get(@item, :maxStackCount, 1)}</div>
        </div>

        <div class="modal-action">
          <button type="button" class="btn" phx-click="close_item">Close</button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_item"></div>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    results = Store.search_items(query)
    {:noreply, assign(socket, search_query: query, search_results: results)}
  end

  def handle_event("search_change", %{"query" => query}, socket) do
    if String.length(query) >= 2 do
      results = Store.search_items(query)
      {:noreply, assign(socket, search_query: query, search_results: results)}
    else
      {:noreply, assign(socket, search_query: query, search_results: [])}
    end
  end

  def handle_event("view_item", %{"id" => id_str}, socket) do
    {id, ""} = Integer.parse(id_str)
    case Store.get_item(id) do
      {:ok, item} ->
        item = Map.put(item, :name, get_item_name(item))
        {:noreply, assign(socket, selected_item: item)}
      :error ->
        {:noreply, put_flash(socket, :error, "Item not found")}
    end
  end

  def handle_event("close_item", _, socket) do
    {:noreply, assign(socket, selected_item: nil)}
  end

  defp get_item_name(item) do
    text_id = Map.get(item, :localizedTextIdName, 0)
    Store.get_localized_text(text_id) || "Item ##{item.id}"
  end

  defp item_quality_class(item) do
    case Map.get(item, :itemQualityId, 1) do
      1 -> "text-gray-400"    # Poor
      2 -> ""                 # Common
      3 -> "text-green-500"   # Uncommon
      4 -> "text-blue-500"    # Rare
      5 -> "text-purple-500"  # Epic
      6 -> "text-orange-500"  # Legendary
      _ -> ""
    end
  end

  defp item_type_name(item) do
    case Map.get(item, :itemType, 0) do
      1 -> "Armor"
      2 -> "Weapon"
      3 -> "Bag"
      4 -> "Consumable"
      5 -> "Currency"
      6 -> "Quest"
      _ -> "Other"
    end
  end
end
```

**Step 2: Add route**

```elixir
# Add to router.ex admin scope
live "/items", Admin.ItemsLive
```

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/
git commit -m "feat(admin): add item database search page"
```

---

### Task 18: Add Item Remove Function

**Files:**
- Modify: `apps/bezgelor_db/lib/bezgelor_db/inventory.ex`
- Test: `apps/bezgelor_db/test/inventory_test.exs`

**Step 1: Write the failing test**

```elixir
# Add to apps/bezgelor_db/test/inventory_test.exs
describe "admin_remove_item/2" do
  test "removes item from inventory" do
    # Setup: create character and add item
    {:ok, character} = create_test_character()
    {:ok, [item]} = Inventory.add_item(character.id, 12345, 1)

    # Remove the item
    assert {:ok, _} = Inventory.admin_remove_item(character.id, item.id)

    # Verify it's gone
    items = Inventory.get_items(character.id)
    refute Enum.any?(items, &(&1.id == item.id))
  end

  test "returns error for non-existent item" do
    {:ok, character} = create_test_character()
    assert {:error, :not_found} = Inventory.admin_remove_item(character.id, 999999)
  end
end
```

**Step 2: Run test to verify it fails**

```bash
mix test apps/bezgelor_db/test/inventory_test.exs --only admin_remove_item
```

**Step 3: Implement admin_remove_item**

```elixir
# Add to apps/bezgelor_db/lib/bezgelor_db/inventory.ex

@doc """
Admin function to remove an item from a character's inventory.
"""
@spec admin_remove_item(integer(), integer()) :: {:ok, InventoryItem.t()} | {:error, atom()}
def admin_remove_item(character_id, item_id) do
  case Repo.get_by(InventoryItem, id: item_id, character_id: character_id) do
    nil ->
      {:error, :not_found}

    item ->
      Repo.delete(item)
  end
end
```

**Step 4: Run test to verify it passes**

**Step 5: Commit**

```bash
git add apps/bezgelor_db/
git commit -m "feat(db): add admin_remove_item function"
```

---

### Task 19: Add Remove Item Button to Admin Character Inventory

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/admin/character_detail_live.ex`

**Step 1: Update inventory_tab to include remove button**

```elixir
# Update inventory_tab in character_detail_live.ex
defp inventory_tab(assigns) do
  ~H"""
  <div class="space-y-6">
    <div>
      <h3 class="font-semibold mb-3">Equipped Items ({length(@equipped_items)})</h3>
      <%= if Enum.empty?(@equipped_items) do %>
        <p class="text-base-content/50">No equipped items</p>
      <% else %>
        <div class="overflow-x-auto">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Slot</th>
                <th>Item ID</th>
                <th>Stack</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @equipped_items}>
                <td>{item.slot}</td>
                <td class="font-mono">{item.item_id}</td>
                <td>{item.quantity}</td>
                <td>
                  <button
                    type="button"
                    class="btn btn-ghost btn-xs text-error"
                    phx-click="remove_item"
                    phx-value-id={item.id}
                    data-confirm="Remove this item?"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    <!-- Similar update for inventory_items table -->
  </div>
  """
end
```

**Step 2: Add event handler**

```elixir
# Add to character_detail_live.ex
@impl true
def handle_event("remove_item", %{"id" => id_str}, socket) do
  admin = socket.assigns.current_account
  character = socket.assigns.character
  {item_id, ""} = Integer.parse(id_str)

  case Inventory.admin_remove_item(character.id, item_id) do
    {:ok, removed} ->
      Authorization.log_action(admin, "character.remove_item", "character", character.id, %{
        item_id: removed.item_id,
        inventory_item_id: item_id
      })

      {:noreply,
       socket
       |> put_flash(:info, "Item removed")
       |> load_tab_data(:inventory)}

    {:error, :not_found} ->
      {:noreply, put_flash(socket, :error, "Item not found")}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to remove item")}
  end
end
```

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/
git commit -m "feat(admin): add item removal from character inventory"
```

---

## Phase 4: User Character Sheet Enhancements

### Task 20: Add Bank Tab to User Character Sheet

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/character_detail_live.ex`

**Step 1: Add :bank to tabs**

```elixir
# Update in character_detail_live.ex
@tabs ~w(overview inventory bank currencies guild tradeskills)a
```

**Step 2: Add tab label**

```elixir
defp tab_label(:bank), do: "Bank"
```

**Step 3: Add render function**

```elixir
defp render_tab_content(%{active_tab: :bank} = assigns), do: render_bank(assigns)

defp render_bank(assigns) do
  ~H"""
  <div class="card bg-base-100 shadow-xl">
    <div class="card-body">
      <h2 class="card-title">
        <.icon name="hero-building-library" class="size-5" />
        Bank Storage
      </h2>
      <%= if Enum.empty?(@bank_items) do %>
        <div class="text-center py-8 text-base-content/50">
          <.icon name="hero-building-library" class="size-12 mx-auto mb-2" />
          <p>Bank is empty</p>
        </div>
      <% else %>
        <div class="overflow-x-auto mt-4">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Slot</th>
                <th>Item ID</th>
                <th>Qty</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @bank_items}>
                <td>Bank {item.bag_index - 10}, Slot {item.slot}</td>
                <td class="font-mono">{item.item_id}</td>
                <td>{item.quantity}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="text-sm text-base-content/50 mt-2">
          {length(@bank_items)} items in bank
        </p>
      <% end %>
    </div>
  </div>
  """
end
```

**Step 4: Add load_tab_data for bank**

```elixir
defp load_tab_data(socket, :bank) do
  character_id = socket.assigns.character.id
  bank_items = Inventory.get_bank_items(character_id)
  assign(socket, bank_items: bank_items)
end
```

**Step 5: Initialize bank_items in mount**

```elixir
# Add to mount assigns
bank_items: []
```

**Step 6: Commit**

```bash
git add apps/bezgelor_portal/
git commit -m "feat(portal): add bank tab to user character sheet"
```

---

### Task 21: Add 3D Character Viewer to User Character Sheet

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/character_detail_live.ex`

**Step 1: Import CharacterViewer component**

```elixir
# Add at top
alias BezgelorPortalWeb.Components.CharacterViewer
```

**Step 2: Add viewer to overview tab**

```elixir
defp render_overview(assigns) do
  ~H"""
  <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
    <!-- 3D Character Viewer -->
    <div class="lg:col-span-1">
      <CharacterViewer.character_viewer
        character={@character}
        equipment={@equipped_items}
        class="h-[400px]"
      />
    </div>

    <!-- Existing info cards -->
    <div class="lg:col-span-2 grid grid-cols-1 md:grid-cols-2 gap-6">
      <!-- Basic Info Card -->
      <div class="card bg-base-100 shadow-xl">
        <!-- existing content -->
      </div>
      <!-- ... other cards ... -->
    </div>
  </div>
  """
end
```

**Step 3: Load equipped items for overview**

```elixir
defp load_tab_data(socket, :overview) do
  character_id = socket.assigns.character.id
  all_items = Inventory.get_items(character_id)
  equipped = Enum.filter(all_items, &(&1.container_type == :equipped))
  assign(socket, equipped_items: equipped)
end
```

**Step 4: Commit**

```bash
git add apps/bezgelor_portal/
git commit -m "feat(portal): add 3D character viewer to character sheet"
```

---

### Task 22: Add Equipment Grid Display

**Files:**
- Modify: `apps/bezgelor_portal/lib/bezgelor_portal_web/live/character_detail_live.ex`

**Step 1: Create equipment slot component**

```elixir
defp equipment_grid(assigns) do
  slots = [
    {:head, "Head", 0},
    {:shoulders, "Shoulders", 1},
    {:chest, "Chest", 2},
    {:hands, "Hands", 3},
    {:legs, "Legs", 4},
    {:feet, "Feet", 5},
    {:weapon_primary, "Main Hand", 6},
    {:weapon_secondary, "Off Hand", 7},
    {:support_system, "Support", 8},
    {:gadget, "Gadget", 9},
    {:implant, "Implant", 10}
  ]

  assigns = assign(assigns, :slots, slots)

  ~H"""
  <div class="card bg-base-100 shadow-xl">
    <div class="card-body">
      <h2 class="card-title">
        <.icon name="hero-shield-check" class="size-5" />
        Equipment
      </h2>
      <div class="grid grid-cols-2 gap-2 mt-4">
        <.equipment_slot
          :for={{slot_key, slot_name, slot_index} <- @slots}
          name={slot_name}
          item={find_equipped(@equipped_items, slot_index)}
        />
      </div>
    </div>
  </div>
  """
end

defp equipment_slot(assigns) do
  ~H"""
  <div class={"p-2 rounded #{if @item, do: "bg-base-200", else: "bg-base-300/50 border border-dashed border-base-300"}"}>
    <div class="text-xs text-base-content/50 mb-1">{@name}</div>
    <%= if @item do %>
      <div class="font-mono text-sm">{@item.item_id}</div>
    <% else %>
      <div class="text-base-content/30 text-sm">Empty</div>
    <% end %>
  </div>
  """
end

defp find_equipped(items, slot_index) do
  Enum.find(items, &(&1.slot == slot_index))
end
```

**Step 2: Add to overview**

```elixir
# In render_overview, add equipment_grid after character viewer
<.equipment_grid equipped_items={@equipped_items} />
```

**Step 3: Commit**

```bash
git add apps/bezgelor_portal/
git commit -m "feat(portal): add equipment grid display to character sheet"
```

---

## Summary

**Phase 1 (M3 Extractor):** 11 tasks - Python tool to extract WildStar .m3 models to glTF

**Phase 2 (Three.js):** 4 tasks - WebGL character viewer integration

**Phase 3 (Admin Items):** 4 tasks - Item search and management

**Phase 4 (User Sheet):** 3 tasks - Bank tab, 3D viewer, equipment grid

**Total:** 22 bite-sized tasks

---

## Decisions Made

- **Animation:** Include skeletal animations (idle/walk/combat) in Phase 1
- **Textures:** Extract at full resolution, downscale at render time via Three.js
- **Caching:** On-demand extraction, then cached as static files
- **Missing models:** Hide viewer, show "Character preview not available" text
