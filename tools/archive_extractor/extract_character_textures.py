"""Batch extract and convert character textures from WildStar archives.

This script:
1. Extracts character-related textures from the archive
2. Attempts to convert them to PNG using tex_extractor
3. Reports which textures could be converted and which need external tools

Usage:
    python extract_character_textures.py <path_to.index> -o ./textures

The output will be organized:
    ./textures/
        converted/      <- Successfully converted PNGs
        raw/            <- Raw .tex files that couldn't be converted
        report.txt      <- Summary of extraction
"""
import argparse
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "m3_extractor"))

from archive_extractor import WildStarArchive
from tex_extractor import TexExtractor


# Patterns for character-related textures
CHARACTER_PATTERNS = [
    "Art/Character/*.tex",
    "Art/Character/**/*.tex",
    "Art/Creature/*.tex",
    "Art/Creature/**/*.tex",
    "Art/Armor/*.tex",
    "Art/Armor/**/*.tex",
    "Art/Weapon/*.tex",
    "Art/Weapon/**/*.tex",
]

# Simpler patterns for testing
TEST_PATTERNS = [
    "Art/UI/*.tex",
    "Art/UI/**/*.tex",
]


def extract_and_convert(archive: WildStarArchive, pattern: str, output_dir: Path,
                        convert: bool = True) -> dict:
    """Extract textures matching pattern and optionally convert to PNG.

    Returns:
        Dict with 'converted', 'raw', 'failed' lists
    """
    results = {
        'converted': [],
        'raw': [],
        'failed': []
    }

    files = archive.list_files(pattern)
    if not files:
        return results

    converted_dir = output_dir / "converted"
    raw_dir = output_dir / "raw"
    converted_dir.mkdir(parents=True, exist_ok=True)
    raw_dir.mkdir(parents=True, exist_ok=True)

    for i, file_path in enumerate(files):
        if (i + 1) % 50 == 0:
            print(f"  Processing {i + 1}/{len(files)}...")

        # Extract from archive
        data = archive.extract_file(file_path)
        if data is None:
            results['failed'].append((file_path, "extraction failed"))
            continue

        # Save raw .tex file
        rel_path = file_path.replace("/", "_").replace("\\", "_")
        raw_path = raw_dir / rel_path
        raw_path.write_bytes(data)

        if not convert:
            results['raw'].append(file_path)
            continue

        # Try to convert with tex_extractor
        try:
            extractor = TexExtractor(str(raw_path))
            if not extractor.load():
                results['raw'].append(file_path)
                continue

            info = extractor.get_info()

            # Check if it's a format we can convert
            png_path = converted_dir / f"{raw_path.stem}.png"

            if extractor.to_png(str(png_path)):
                results['converted'].append(file_path)
                # Remove raw file since we have PNG
                raw_path.unlink()
            else:
                # Keep raw file for external conversion
                results['raw'].append(file_path)

        except Exception as e:
            results['raw'].append(file_path)

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Extract and convert character textures from WildStar archives"
    )
    parser.add_argument("index", help="Path to .index file")
    parser.add_argument("--output", "-o", default="./textures",
                       help="Output directory")
    parser.add_argument("--pattern", "-p",
                       help="Custom glob pattern (default: character textures)")
    parser.add_argument("--test", action="store_true",
                       help="Test with UI textures (smaller, mostly convertible)")
    parser.add_argument("--no-convert", action="store_true",
                       help="Extract only, don't convert to PNG")
    parser.add_argument("--limit", type=int, default=0,
                       help="Limit number of files to process (0 = all)")

    args = parser.parse_args()

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Opening archive: {args.index}")

    try:
        with WildStarArchive(args.index) as archive:
            # Determine patterns to use
            if args.pattern:
                patterns = [args.pattern]
            elif args.test:
                patterns = TEST_PATTERNS
                print("Test mode: extracting UI textures")
            else:
                patterns = CHARACTER_PATTERNS
                print("Extracting character textures")

            all_results = {
                'converted': [],
                'raw': [],
                'failed': []
            }

            for pattern in patterns:
                print(f"\nPattern: {pattern}")
                files = archive.list_files(pattern)

                if args.limit > 0:
                    files = files[:args.limit]

                print(f"  Found {len(files)} files")

                if files:
                    results = extract_and_convert(
                        archive, pattern, output_dir,
                        convert=not args.no_convert
                    )
                    for key in all_results:
                        all_results[key].extend(results[key])

            # Print summary
            print("\n" + "=" * 60)
            print("EXTRACTION SUMMARY")
            print("=" * 60)
            print(f"Successfully converted to PNG: {len(all_results['converted'])}")
            print(f"Extracted as raw .tex:         {len(all_results['raw'])}")
            print(f"Failed to extract:             {len(all_results['failed'])}")

            # Write report
            report_path = output_dir / "report.txt"
            with open(report_path, "w") as f:
                f.write("WildStar Texture Extraction Report\n")
                f.write("=" * 60 + "\n\n")

                f.write(f"Converted to PNG ({len(all_results['converted'])}):\n")
                for p in sorted(all_results['converted']):
                    f.write(f"  {p}\n")

                f.write(f"\nRaw .tex files ({len(all_results['raw'])}):\n")
                f.write("(These need external conversion - use WildStar Studio)\n")
                for p in sorted(all_results['raw']):
                    f.write(f"  {p}\n")

                f.write(f"\nFailed ({len(all_results['failed'])}):\n")
                for p, reason in all_results['failed']:
                    f.write(f"  {p}: {reason}\n")

            print(f"\nReport written to: {report_path}")
            print(f"Converted PNGs in: {output_dir / 'converted'}")
            print(f"Raw .tex files in: {output_dir / 'raw'}")

            if all_results['raw']:
                print("\n" + "-" * 60)
                print("NOTE: Some textures use complex type-3 compression.")
                print("Use WildStar Studio to convert the raw .tex files in the 'raw' folder.")

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        return 1

    return 0


if __name__ == "__main__":
    exit(main())
