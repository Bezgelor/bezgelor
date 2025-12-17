# WildStar Archive Extractor

Python tools for extracting files from WildStar game archives (.index/.archive pairs).

## Requirements

- Python 3.8+
- No external dependencies for basic extraction
- Pillow (optional, for PNG conversion)

```bash
pip install Pillow
```

## Usage

### List files in archive

```bash
# Show archive stats
python archive_extractor.py "C:\Path\To\ClientData.index"

# List all .tex files
python archive_extractor.py "C:\Path\To\ClientData.index" --list "*.tex"

# List character textures
python archive_extractor.py "C:\Path\To\ClientData.index" --list "Art/Character/**/*.tex"
```

### Extract files

```bash
# Extract all textures
python archive_extractor.py "C:\Path\To\ClientData.index" --extract "*.tex" -o ./textures

# Extract specific path
python archive_extractor.py "C:\Path\To\ClientData.index" --extract "Art/Character/Human/*.tex" -o ./output
```

### Batch extract character textures with conversion

```bash
# Test with UI textures (mostly convertible)
python extract_character_textures.py "C:\Path\To\ClientData.index" --test -o ./test_textures

# Extract all character textures
python extract_character_textures.py "C:\Path\To\ClientData.index" -o ./character_textures

# Limit to first 100 files
python extract_character_textures.py "C:\Path\To\ClientData.index" --limit 100 -o ./sample
```

## Output Structure

The `extract_character_textures.py` script creates:

```
output/
  converted/     # PNG files (successfully converted)
  raw/           # .tex files (need external conversion)
  report.txt     # Summary of extraction
```

## Texture Conversion Notes

The tex_extractor can convert:
- ✅ Simple type-3 textures (DXT1/DXT3/DXT5 with count=0)
- ✅ Standard type-0 textures

The following require WildStar Studio or other external tools:
- ❌ Complex type-3 textures (custom compression, format=0, count>0)

See `docs/formats/tex-type3-format.md` for details on the texture format.

## Archive Format

Based on reverse engineering of WildStar Studio source code:

- `.index` file: Contains file tree, names, SHA hashes, and metadata
- `.archive` file: Contains AARC lookup table and actual file data
- Files with flags=3 are zlib compressed in the archive
- Files are looked up by SHA-1 hash

## Troubleshooting

### "File not found"
Make sure both `.index` and `.archive` files exist in the same directory.

### "Decompression failed"
The file may be corrupted or use an unsupported compression method.

### "Type 3 textures with custom compression not yet supported"
These textures need to be converted using WildStar Studio (Windows GUI tool).
