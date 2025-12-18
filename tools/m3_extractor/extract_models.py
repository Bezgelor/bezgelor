#!/usr/bin/env python3
"""Extract WildStar M3 models to glTF format.

Usage:
    python extract_models.py <input> [-o <output>] [--no-skeleton] [--no-animation]

Examples:
    # Extract a single file
    python extract_models.py character.m3 -o ./output

    # Extract all M3 files from a directory
    python extract_models.py ./models/ -o ./output

    # Extract without skeleton/animation
    python extract_models.py character.m3 -o ./output --no-skeleton --no-animation
"""
import argparse
import os
import sys
from pathlib import Path

from gltf_exporter import GLTFExporter


def main():
    parser = argparse.ArgumentParser(
        description="Extract WildStar M3 models to glTF format"
    )
    parser.add_argument(
        "input",
        help="Input M3 file or directory containing M3 files",
    )
    parser.add_argument(
        "-o", "--output",
        default="./output",
        help="Output directory for glTF files (default: ./output)",
    )
    parser.add_argument(
        "--no-skeleton",
        action="store_true",
        help="Skip skeleton export",
    )
    parser.add_argument(
        "--no-animation",
        action="store_true",
        help="Skip animation export",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output",
    )

    args = parser.parse_args()

    # Ensure output directory exists
    os.makedirs(args.output, exist_ok=True)

    # Collect input files
    input_path = Path(args.input)
    if input_path.is_file():
        files = [input_path]
    elif input_path.is_dir():
        files = list(input_path.glob("**/*.m3"))
        if not files:
            print(f"No M3 files found in {input_path}", file=sys.stderr)
            return 1
    else:
        print(f"Input not found: {args.input}", file=sys.stderr)
        return 1

    # Export options
    include_skeleton = not args.no_skeleton
    include_animations = not args.no_animation

    success_count = 0
    fail_count = 0

    for m3_file in files:
        output_file = Path(args.output) / f"{m3_file.stem}.glb"

        try:
            exporter = GLTFExporter(str(m3_file))
            exporter.export(
                str(output_file),
                include_skeleton=include_skeleton,
                include_animations=include_animations,
            )
            if args.verbose:
                print(f"Exported: {m3_file} -> {output_file}")
            success_count += 1
        except Exception as e:
            print(f"Failed: {m3_file} - {e}", file=sys.stderr)
            fail_count += 1

    # Summary
    total = success_count + fail_count
    print(f"\nExtracted {success_count}/{total} files to {args.output}")

    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
