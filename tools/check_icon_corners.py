#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image


def _alpha_at(image: Image.Image, x: int, y: int) -> int:
    return int(image.getpixel((x, y))[3])


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check that an RGBA PNG has transparent corners (for macOS Dock icons)."
    )
    parser.add_argument(
        "--path",
        default="assets/icon/app_icon_macos.png",
        help="Path to the PNG file (relative to the repo root).",
    )
    parser.add_argument(
        "--max-corner-alpha",
        type=int,
        default=0,
        help="Maximum allowed alpha value at the four corners (0-255).",
    )
    parser.add_argument(
        "--min-center-alpha",
        type=int,
        default=250,
        help="Minimum required alpha value at the image center (0-255).",
    )
    args = parser.parse_args()

    path = Path(args.path)
    if not path.exists():
        print(f"ERROR: Missing file: {path}", file=sys.stderr)
        return 2

    image = Image.open(path).convert("RGBA")
    width, height = image.size

    corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
    corner_alphas = [_alpha_at(image, x, y) for x, y in corners]

    if any(alpha > args.max_corner_alpha for alpha in corner_alphas):
        details = ", ".join(
            f"({x},{y})={alpha}" for (x, y), alpha in zip(corners, corner_alphas)
        )
        print(
            f"ERROR: Corners are not transparent enough: {details}",
            file=sys.stderr,
        )
        return 1

    center_alpha = _alpha_at(image, width // 2, height // 2)
    if center_alpha < args.min_center_alpha:
        print(
            f"ERROR: Center alpha too low: {center_alpha} < {args.min_center_alpha}",
            file=sys.stderr,
        )
        return 1

    print(
        f"OK: {path} {width}x{height} corners={corner_alphas} center={center_alpha}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
