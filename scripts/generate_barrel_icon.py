#!/usr/bin/env python3
"""Generates the BARREL app icon (1024x1024 PNG, black background, gold
outlined barrel centered) into Assets.xcassets/AppIcon.appiconset/AppIcon.png.

The barrel is rendered as a semicircle-capped wedge tapering to a sharp
point — same proportions as the primary logo on the brand sheet.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICON_PATH = ROOT / "BaseballStatTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

ICON_SIZE = 1024
BG = (10, 10, 12, 255)          # near-black #0A0A0C (same as marketing canvas)
GOLD = (212, 175, 55, 255)      # #D4AF37

# Barrel geometry (inside icon canvas)
BARREL_W = int(ICON_SIZE * 0.78)         # total horizontal extent
BARREL_H = int(BARREL_W * 0.22)          # thick-end height
STROKE = max(14, ICON_SIZE // 64)        # ~16 px at 1024 — scales with icon


def barrel_polygon(cx: int, cy: int, width: int, height: int, steps: int = 48):
    """Build a polygon for a barrel shape.

    Origin at left edge of the cap circle; right end is a sharp point.
    Thick (left) half is a semicircle cap; the top + bottom edges taper
    linearly to the point.
    """
    r = height / 2
    left_cap_center_x = cx - width / 2 + r
    point_x = cx + width / 2
    point_y = cy

    # Semicircle cap: sweep from top (angle = -90°) CCW around to bottom (90°)
    # via 180° (left-most point). In screen coords (y grows down), that means
    # we walk from (cap_cx, cy - r) over the left side down to (cap_cx, cy + r).
    pts = []
    for i in range(steps + 1):
        # Angle from top, going counter-clockwise (left side of circle)
        t = math.pi * i / steps  # 0..π
        # Standard math: (cos, sin) where angle measured from +x axis
        # Start at top (90°) sweep through 180° to 270° (or -90°)
        angle = math.pi / 2 + t  # π/2 → 3π/2
        x = left_cap_center_x + r * math.cos(angle)
        y = cy - r * math.sin(angle)  # flip sin for screen y
        pts.append((x, y))
    # Now append the sharp point
    pts.append((point_x, point_y))
    return pts


def main():
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), BG)
    draw = ImageDraw.Draw(img)

    cx = ICON_SIZE // 2
    cy = ICON_SIZE // 2
    pts = barrel_polygon(cx, cy, BARREL_W, BARREL_H)

    # Draw the outline — polygon with no fill.
    draw.polygon(pts, outline=GOLD, fill=None, width=STROKE)

    ICON_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(ICON_PATH, format="PNG")
    print(f"✓ wrote {ICON_PATH}  ({ICON_SIZE}×{ICON_SIZE})")


if __name__ == "__main__":
    main()
