#!/usr/bin/env python3
"""Primary BARREL app icon: near-black canvas, gold two-cap barrel, tilted."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

from barrel_geometry import build_barrel_polygon

ROOT = Path(__file__).resolve().parent.parent
ICON_PATH = ROOT / "BaseballStatTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

ICON_SIZE = 1024
BG = (10, 10, 12, 255)         # near-black #0A0A0C
GOLD = (212, 175, 55, 255)     # #D4AF37
SHAPE_W_FRAC = 0.78
STROKE_FRAC = 1 / 72           # ~14 px at 1024


def main():
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), BG)
    draw = ImageDraw.Draw(img)
    pts = build_barrel_polygon(
        center_x=ICON_SIZE / 2,
        center_y=ICON_SIZE / 2,
        shape_w=ICON_SIZE * SHAPE_W_FRAC,
    )
    stroke = max(3, int(ICON_SIZE * STROKE_FRAC))
    draw.polygon(pts, outline=GOLD, fill=None, width=stroke)
    ICON_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(ICON_PATH, format="PNG")
    print(f"✓ wrote {ICON_PATH} ({ICON_SIZE}×{ICON_SIZE})")


if __name__ == "__main__":
    main()
