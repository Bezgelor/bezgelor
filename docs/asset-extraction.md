# Asset Extraction Guide

This guide explains how to extract 3D character models and textures from your WildStar game client for use with the Bezgelor portal's character viewer.

> **Legal Note**: These assets are proprietary to NCSOFT and cannot be redistributed. You must extract them from your own legally-obtained game client.

## Overview

The extraction pipeline:

1. **Extract files from archives** → Use `archive_extractor` to pull .m3 and .tex files from ClientData.archive
2. **Convert M3 to glTF** → Use `m3_extractor` to convert WildStar models to web-compatible format
3. **Convert TEX to PNG** → Use `tex_extractor` to convert WildStar textures to standard images
4. **Deploy assets** → Copy to portal static directory or upload to private storage

## Prerequisites

- Python 3.8+
- WildStar game client (with ClientData.index and ClientData.archive)
- ~2GB free disk space for extracted assets

```bash
# Install Python dependencies
pip install Pillow numpy pygltflib
```

## Step 1: Locate Game Files

Find your WildStar installation. You need:
- `ClientData.index` - File index/metadata
- `ClientData.archive` - Actual file data

Common locations:
```
C:\Program Files (x86)\NCSOFT\WildStar\Patch\ClientData.index
C:\Program Files (x86)\Steam\steamapps\common\WildStar\Patch\ClientData.index
```

## Step 2: Extract Character Models

### 2a. List available models

```bash
cd tools/archive_extractor

# See what character models are available
python archive_extractor.py "C:\Path\To\ClientData.index" --list "Art/Character/*/*.m3"
```

### 2b. Extract M3 files

```bash
# Extract all character M3 files
python archive_extractor.py "C:\Path\To\ClientData.index" \
  --extract "Art/Character/*/*.m3" \
  -o ./extracted_models
```

### 2c. Convert M3 to glTF

```bash
cd ../m3_extractor

# Set up virtual environment (first time only)
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Convert all extracted models
python extract_models.py ../archive_extractor/extracted_models/ -o ./output

# Or convert specific models
python extract_models.py path/to/Human_Male.m3 -o ./output
```

### 2d. Rename for portal

The portal expects models named `{race}_{gender}.glb`:

```bash
# Example renaming (adjust paths as needed)
mv output/Human_Male.glb human_male.glb
mv output/Human_Female.glb human_female.glb
mv output/Granok_Male.glb granok_male.glb
mv output/Granok_Female.glb granok_female.glb
mv output/Aurin_Male.glb aurin_male.glb
mv output/Aurin_Female.glb aurin_female.glb
mv output/Draken_Male.glb draken_male.glb
mv output/Draken_Female.glb draken_female.glb
mv output/Mechari_Male.glb mechari_male.glb
mv output/Mechari_Female.glb mechari_female.glb
mv output/Chua.glb chua_male.glb        # Chua are genderless
cp chua_male.glb chua_female.glb
mv output/Mordesh_Male.glb mordesh_male.glb
mv output/Mordesh_Female.glb mordesh_female.glb
# Cassian uses Human models
cp human_male.glb cassian_male.glb
cp human_female.glb cassian_female.glb
```

## Step 3: Extract Textures

### 3a. List available textures

```bash
cd tools/archive_extractor

# List character textures
python archive_extractor.py "C:\Path\To\ClientData.index" --list "Art/Character/**/*.tex"
```

### 3b. Extract and convert textures

```bash
# Use the batch extraction script
python extract_character_textures.py "C:\Path\To\ClientData.index" -o ./extracted_textures

# Or extract specific textures manually
python archive_extractor.py "C:\Path\To\ClientData.index" \
  --extract "Art/Character/Human/**/*.tex" \
  -o ./raw_textures

# Then convert with tex_extractor
cd ../m3_extractor
python tex_extractor.py ../archive_extractor/raw_textures/ -o ./converted_textures
```

### 3c. Organize textures

The portal expects this structure:
```
textures/
  characters/
    Human/
      Male/
        CHR_Human_M_Skin_*.png
      Female/
        CHR_Human_F_Skin_*.png
    Draken/
      Male/
        CHR_DrakenMale_Skin_*.png
      Female/
        CHR_Draken_F_*.png
    ...
```

## Step 4: Deploy Assets

### Option A: Copy directly to portal

For development or single-server deployments:

```bash
# Models
cp -r output/*.glb apps/bezgelor_portal/priv/static/models/characters/

# Textures
cp -r converted_textures/* apps/bezgelor_portal/priv/static/textures/
```

### Option B: Upload to private storage

For production deployments, upload to your private storage:

```bash
# To S3
aws s3 sync output/ s3://my-bucket/bezgelor-assets/models/characters/
aws s3 sync converted_textures/ s3://my-bucket/bezgelor-assets/textures/

# To a server
rsync -av output/ user@server:/assets/bezgelor/models/characters/
rsync -av converted_textures/ user@server:/assets/bezgelor/textures/
```

Then fetch during deployment:
```bash
export BEZGELOR_ASSETS_URL="s3://my-bucket/bezgelor-assets"
mix assets.fetch
```

## Texture Conversion Limitations

Not all textures can be converted automatically:

| Status | Format | Notes |
|--------|--------|-------|
| ✅ Works | DXT1/DXT3/DXT5 with count=0 | ~18% of textures |
| ❌ Needs work | Type-3 with count>0 | Custom compression, see [GitHub issue #44](https://github.com/Bezgelor/bezgelor/issues/44) |

For unconvertible textures, you may need to use [WildStar Studio](https://github.com/Flavor/WildStar-Studio) on Windows.

## Troubleshooting

### "File not found" when extracting
Make sure both `.index` and `.archive` files are in the same directory.

### Model appears but has no texture
Check that the texture file exists and the path matches what `character_viewer.js` expects. See the `textureMap` in that file.

### Model is invisible or distorted
The M3 format is complex. Some models may not convert correctly. Try with `--no-animation` flag.

### Python module not found
Make sure you activated the virtual environment:
```bash
source venv/bin/activate  # or venv\Scripts\activate on Windows
```

## File Locations Reference

| Asset Type | Source Path in Archive | Destination |
|------------|----------------------|-------------|
| Character models | `Art/Character/{Race}/*.m3` | `priv/static/models/characters/{race}_{gender}.glb` |
| Skin textures | `Art/Character/{Race}/*Skin*.tex` | `priv/static/textures/characters/{Race}/{Gender}/*.png` |
| Armor textures | `Art/Character/{Race}/*Armor*.tex` | `priv/static/textures/characters/{Race}/Armor/*.png` |

## Tools Reference

| Tool | Purpose | Location |
|------|---------|----------|
| `archive_extractor.py` | Extract files from .archive | `tools/archive_extractor/` |
| `extract_character_textures.py` | Batch extract character textures | `tools/archive_extractor/` |
| `extract_models.py` | Convert M3 to glTF | `tools/m3_extractor/` |
| `tex_extractor.py` | Convert TEX to PNG | `tools/m3_extractor/` |
| `mix assets.fetch` | Download from private storage | Elixir mix task |

## See Also

- [tools/archive_extractor/README.md](../tools/archive_extractor/README.md) - Archive extractor details
- [tools/m3_extractor/README.md](../tools/m3_extractor/README.md) - Model extractor details
- [GitHub Issue #44](https://github.com/Bezgelor/bezgelor/issues/44) - Type-3 texture compression research
