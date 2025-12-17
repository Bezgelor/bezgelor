# WildStar M3 Model Extractor

Extracts WildStar .m3 model files and converts them to glTF/GLB format for use with Three.js.

## Installation

```bash
cd tools/m3_extractor
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## Usage

### Extract a single model

```bash
python extract_models.py path/to/model.m3 -o output/
```

### Batch extract

```bash
python extract_models.py path/to/models/ -o output/
```

### Options

- `-o, --output` - Output directory (default: `./output`)
- `--no-skeleton` - Skip skeleton/bone export
- `--no-animation` - Skip animation export

## Output

Produces `.glb` files (binary glTF) compatible with Three.js GLTFLoader.

## Development

Run tests:

```bash
python -m pytest tests/ -v
```

## Format Documentation

See [docs/formats/m3-format.md](../../docs/formats/m3-format.md) for M3 file format details.
