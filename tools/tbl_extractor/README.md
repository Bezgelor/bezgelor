# WildStar Data Extraction Tools

Python tools to extract data from WildStar's game files and convert them to JSON for use with Bezgelor.

## Requirements

- Python 3.8+
- No external dependencies

## Tools

| Tool | Description |
|------|-------------|
| `tbl_extractor.py` | Extract `.tbl` (ClientDB) files to JSON |
| `extract_game_data.py` | Batch extract game tables for Bezgelor |
| `language_extractor.py` | Extract localized text strings from language files |

## tbl_extractor.py - Table Extractor

Extracts data from WildStar's `.tbl` (ClientDB) files.

### Usage

```bash
# Extract to same directory with .json extension
python tbl_extractor.py Creature2.tbl

# Extract to specific output file
python tbl_extractor.py Creature2.tbl creatures.json

# Batch extract all .tbl files
python tbl_extractor.py --batch ./tbl ./json

# Show structure without extracting
python tbl_extractor.py --info Creature2.tbl
```

### Output Format

```json
{
  "creature2": [
    {"id": 1, "name": "Training Dummy", ...},
    ...
  ]
}
```

## extract_game_data.py - Bezgelor Data Extractor

Extracts and transforms specific tables needed by the Bezgelor server.

### Usage

```bash
# Extract from tbl directory to default output (priv/data/)
python extract_game_data.py /path/to/tbl/

# Extract to specific output directory
python extract_game_data.py /path/to/tbl/ /path/to/output/
```

### Extracted Tables

| Source File | Output | Content |
|-------------|--------|---------|
| `Creature2.tbl` | `creatures.json` | NPC/creature templates |
| `WorldZone.tbl` | `zones.json` | Zone definitions |
| `Spell4.tbl` | `spells.json` | Spell/ability data |
| `Item2.tbl` | `items.json` | Item templates |

## language_extractor.py - Localized Text Extractor

Extracts human-readable text strings from WildStar's language files (e.g., `en-US.bin`).

### Usage

```bash
# Extract to same directory with .json extension
python language_extractor.py en-US.bin

# Extract to specific output file
python language_extractor.py en-US.bin texts.json

# Show file info without extracting
python language_extractor.py --info en-US.bin
```

### Getting Language Files

Language files are in a separate archive from the main game data:

1. Locate `ClientDataEN.archive` in your WildStar installation (~1.3 GB)
2. Extract `en-US.bin` using an archive extractor (same tools as for .tbl files)
3. Run the language extractor on the extracted file

### Output Format

```json
{
  "texts": {
    "1": "Canary Flower Cluster",
    "2": "Helmsman Malini's Helmet",
    "51": "English",
    ...
  }
}
```

Text IDs correspond to `*_text_id` fields in other tables (e.g., `name_text_id` in creatures, zones, items).

## Getting Source Files

### .tbl Files (Game Tables)

Located in `ClientData.archive`. Extract using:

**Option 1: NexusForever's MapGenerator**
1. Download [NexusForever](https://github.com/NexusForever/NexusForever)
2. Build and run the MapGenerator tool
3. Point it at your WildStar client installation
4. Find extracted `.tbl` files in the `tbl/` output folder

**Option 2: WildStar Archive Extractor**
Use tools like [WildStar Studio](https://www.ownedcore.com/forums/mmo/wildstar/wildstar-bots-programs/448310-wildstar-studio-file-viewer-explorer.html) to extract from archives.

### Language Files

Located in language-specific archives:
- `ClientDataEN.archive` - English (en-US.bin)
- `ClientDataDE.archive` - German (de-DE.bin)
- `ClientDataFR.archive` - French (fr-FR.bin)

## Technical Details

### .tbl File Format

Based on [NexusForever](https://github.com/NexusForever/NexusForever) research.

**Header (104 bytes)**
| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 4 | Signature (0x4C424454 = "TBLD") |
| 0x04 | 4 | Version |
| 0x08 | 8 | Name length |
| 0x10 | 8 | Unknown |
| 0x18 | 8 | Record size |
| 0x20 | 8 | Field count |
| 0x28 | 8 | Field offset |
| 0x30 | 8 | Record count |
| 0x38 | 8 | Total record size |
| 0x40 | 8 | Record offset |
| 0x48 | 8 | Max ID |
| 0x50 | 8 | Lookup offset |
| 0x58 | 8 | Unknown |

**Data Types**
| ID | Type | Size |
|----|------|------|
| 3 | uint32 | 4 bytes |
| 4 | float | 4 bytes |
| 11 | bool | 4 bytes |
| 20 | uint64 | 8 bytes |
| 130 | string | 8 bytes (offset pair) |

### Language File Format (en-US.bin)

Reverse-engineered for this project.

**Header**
| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 4 | Magic ("XETL") |
| 0x0C | 4 | Locale ID (1033 = en-US) |
| 0x40 | 8 | Entry count |
| 0xA0 | - | Index table starts |

**Index Table (at 0xA0)**
- Array of (text_id: uint32, char_offset: uint32) pairs
- Sorted by text_id for binary search
- char_offset * 2 = byte offset from string section start
- char_offset = 0 means empty string

**String Section**
- Starts after index table (typically ~0x41D438)
- UTF-16LE encoded null-terminated strings
- ~509K non-empty + ~30K empty strings for en-US

## Credits

- .tbl format reverse engineering: [NexusForever](https://github.com/NexusForever/NexusForever) project
- Language file format: Bezgelor project (reverse-engineered)
- Original research: Cromon, DrakeFish, and the WildStar emulation community
