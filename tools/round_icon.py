#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a rounded-corner version of a square PNG (transparent corners)."
    )
    parser.add_argument(
        "--in",
        dest="input_path",
        default="assets/icon/app_icon.png",
        help="Input PNG path (relative to the repo root).",
    )
    parser.add_argument(
        "--out",
        dest="output_path",
        default="assets/icon/app_icon_macos.png",
        help="Output PNG path (relative to the repo root).",
    )
    parser.add_argument(
        "--radius-ratio",
        type=float,
        default=0.22,
        help="Corner radius as a fraction of the shortest side (e.g. 0.22).",
    )
    parser.add_argument(
        "--radius",
        type=int,
        default=None,
        help="Corner radius in pixels (overrides --radius-ratio).",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    input_path = Path(args.input_path)
    output_path = Path(args.output_path)

    if not input_path.exists():
        print(f"ERROR: Input file not found: {input_path}", file=sys.stderr)
        return 2

    image = Image.open(input_path).convert("RGBA")
    width, height = image.size
    shortest = min(width, height)

    radius = int(args.radius) if args.radius is not None else int(shortest * args.radius_ratio)
    if radius <= 0:
        print("ERROR: radius must be > 0", file=sys.stderr)
        return 2

    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=255)

    existing_alpha = image.getchannel("A")
    combined_alpha = ImageChops.multiply(existing_alpha, mask)
    image.putalpha(combined_alpha)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path, format="PNG")

    print(f"Wrote {output_path} (radius={radius}px, size={width}x{height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
