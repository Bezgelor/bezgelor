# BezgelorData

Static game data loading and caching via ETS tables.

## Features

- Load game data from JSON files in `priv/data/`
- ETF caching for fast startup (compiled to `priv/compiled/`)
- ETS-based runtime storage for O(1) lookups
- Data types: creatures, spells, items, zones, quests, etc.

## Data Flow

1. JSON source files in `priv/data/` (tracked in git)
2. Compiled to ETF format in `priv/compiled/` (gitignored)
3. Loaded into ETS tables on application start

## Usage

```elixir
# Get a creature definition
creature = BezgelorData.Store.get(:creatures, creature_id)

# Get a spell
spell = BezgelorData.Store.get(:spells, spell_id)

# Check if an item exists
exists? = BezgelorData.Store.exists?(:items, item_id)
```

## Data Extraction

Use Python tools in `tools/tbl_extractor/` to extract data from WildStar game files.
