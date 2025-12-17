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

- Models: `.glb` files (binary glTF) compatible with Three.js GLTFLoader
- Textures: `.png` or `.dds` files

## Texture Extraction

Extract WildStar .tex texture files to PNG or DDS format:

```bash
# Extract single texture to PNG
python tex_extractor.py path/to/texture.tex -o output/

# Extract to DDS format
python tex_extractor.py path/to/texture.tex -o output/ --format dds

# Show texture info without extracting
python tex_extractor.py path/to/texture.tex --info

# Batch extract
python tex_extractor.py path/to/textures/ -o output/
```

### TEX Format Support

- DXT1, DXT3, DXT5 compressed textures
- Uncompressed RGBA/RGB textures
- All mipmap levels

## Development

Run tests:

```bash
python -m pytest tests/ -v
```

## Format Documentation

See [docs/formats/m3-format.md](../../docs/formats/m3-format.md) for M3 file format details.

## Credits

- **M3 Format Research**: [akderebur](https://gist.github.com/akderebur) - WildStar M3 parsing reference and offset documentation
- **Halon Archive Extractor**: Used to extract M3 files from WildStar .archive files
