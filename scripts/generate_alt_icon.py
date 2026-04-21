#!/usr/bin/env python3
"""Generates the BARREL night/alternate app icon: gold background, black
barrel outline. Alt icons must be loose PNG files in the bundle at 120x120
(@2x) and 180x180 (@3x), so we emit both sizes into the target sources.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
# Alt icons must live at the .app bundle root; put them next to Swift sources
# and the Xcode resources phase copies them flat into the bundle.
OUT_DIR = ROOT / "BaseballStatTracker"

GOLD = (212, 175, 55, 255)
INK = (10, 10, 12, 255)


def barrel_polygon(cx, cy, width, height, steps=48):
    r = height / 2
    left_cap_center_x = cx - width / 2 + r
    point_x = cx + width / 2
    point_y = cy
    pts = []
    for i in range(steps + 1):
        t = math.pi * i / steps
        angle = math.pi / 2 + t
        x = left_cap_center_x + r * math.cos(angle)
        y = cy - r * math.sin(angle)
        pts.append((x, y))
    pts.append((point_x, point_y))
    return pts


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), GOLD)
    draw = ImageDraw.Draw(img)
    cx = size // 2
    cy = size // 2
    bw = int(size * 0.78)
    bh = int(bw * 0.22)
    stroke = max(3, size // 64)
    pts = barrel_polygon(cx, cy, bw, bh)
    draw.polygon(pts, outline=INK, fill=None, width=stroke)
    return img


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for suffix, size in [("", 120), ("@2x", 120), ("@3x", 180)]:
        # iOS alternate icons: base name is <Name>.png (60pt @2x = 120, @3x = 180)
        # Standard Apple convention is filename@2x.png and filename@3x.png;
        # iOS auto-selects the right size at runtime from the CFBundleIconFiles
        # entry referencing the base name.
        pass
    # Emit @2x (120) and @3x (180).
    render(120).save(OUT_DIR / "BarrelNight@2x.png", "PNG")
    render(180).save(OUT_DIR / "BarrelNight@3x.png", "PNG")
    # Marketing-size copy for reference (not bundled).
    render(1024).save(ROOT / "docs" / "marketing" / "BarrelNight1024.png", "PNG")
    print(f"✓ wrote alt icons to {OUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
