#!/usr/bin/env python3
"""Alternate "night" BARREL icon: gold background, black two-cap barrel.

Alt icons are loose PNGs at the bundle root (not inside .appiconset).
iOS selects the right size at runtime using the `CFBundleIconFiles` entry
in Info.plist that references the base name (`BarrelNight`).
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

from barrel_geometry import build_barrel_polygon

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "BaseballStatTracker"

GOLD = (212, 175, 55, 255)
INK = (10, 10, 12, 255)
SHAPE_W_FRAC = 0.78


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), GOLD)
    draw = ImageDraw.Draw(img)
    pts = build_barrel_polygon(
        center_x=size / 2,
        center_y=size / 2,
        shape_w=size * SHAPE_W_FRAC,
    )
    stroke = max(3, size // 72)
    draw.polygon(pts, outline=INK, fill=None, width=stroke)
    return img


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    render(120).save(OUT_DIR / "BarrelNight@2x.png", "PNG")
    render(180).save(OUT_DIR / "BarrelNight@3x.png", "PNG")
    render(1024).save(ROOT / "docs" / "marketing" / "BarrelNight1024.png", "PNG")
    print(f"✓ wrote alt icons to {OUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
