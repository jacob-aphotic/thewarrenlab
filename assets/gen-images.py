#!/usr/bin/env python3
"""
gen-images.py — Lapin Logistics asset generator: plain JPEG images.

Usage:
    python3 assets/gen-images.py --outdir <directory>

Outputs (always written; overwrites any existing files):
    team_photo.jpg      — 800x600 solid colour JPEG
    warehouse_crew.jpg  — 1024x768 solid colour JPEG
    harvest_day.jpg     — 1024x768 solid colour JPEG
    office_lunch.jpg    — 1024x768 solid colour JPEG

Exit codes:
    0  success
    1  argument/dependency error
"""

import argparse
import os
import sys


def parse_args():
    p = argparse.ArgumentParser(description="Generate Lapin Logistics JPEG images")
    p.add_argument("--outdir", required=True, help="Directory to write generated files into")
    return p.parse_args()


# ---------------------------------------------------------------------------
# Image generator
# ---------------------------------------------------------------------------

def make_jpeg(outdir: str, filename: str, size: tuple, color: tuple) -> str:
    """Write a plain solid-colour JPEG with no EXIF metadata."""
    from PIL import Image

    path = os.path.join(outdir, filename)
    img = Image.new("RGB", size, color=color)
    img.save(path, format="JPEG", quality=85)
    return path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = parse_args()
    outdir = args.outdir

    try:
        from PIL import Image  # noqa: F401
    except ImportError as exc:
        print(f"[ERROR] Missing dependency: {exc}", file=sys.stderr)
        print("Install with: pip install Pillow", file=sys.stderr)
        sys.exit(1)

    os.makedirs(outdir, exist_ok=True)

    files = []

    for filename, size, color in (
        ("team_photo.jpg",     (800, 600),  (180, 30, 30)),
        ("warehouse_crew.jpg", (1024, 768), (120, 100, 80)),
        ("harvest_day.jpg",    (1024, 768), (90, 110, 60)),
        ("office_lunch.jpg",   (1024, 768), (200, 180, 140)),
    ):
        path = make_jpeg(outdir, filename, size, color)
        print(f"[gen-images] wrote {path}")
        files.append(path)

    print(f"[gen-images] done — {len(files)} files written to {outdir}")


if __name__ == "__main__":
    main()
