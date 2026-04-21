#!/usr/bin/env python3
"""Horizontal BARREL banner for the GitHub README.

Reuses the shared barrel geometry + wordmark code; output lands at
docs/banner.png (1600x500). The README reads this file directly.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

from barrel_geometry import build_barrel_polygon
from generate_barrel_icon import draw_wordmark

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "banner.png"

W, H = 1600, 500
BG = (10, 10, 12, 255)            # #0A0A0C
GOLD = (212, 175, 55, 255)        # #D4AF37

BARREL_W_FRAC = 0.32              # barrel fills ~half the banner width
BARREL_CX_FRAC = 0.50
BARREL_CY_FRAC = 0.40
WORDMARK_CY_FRAC = 0.78
WORDMARK_PX = 132
STROKE_FRAC = 1 / 112             # thinner stroke at wider canvas


def main():
    img = Image.new("RGBA", (W, H), BG)
    draw = ImageDraw.Draw(img)

    pts = build_barrel_polygon(
        center_x=int(W * BARREL_CX_FRAC),
        center_y=int(H * BARREL_CY_FRAC),
        shape_w=int(W * BARREL_W_FRAC),
    )
    # Base the stroke on the barrel's width so the line weight stays
    # proportional to the mark itself, not to the banner canvas.
    stroke = max(4, int(W * BARREL_W_FRAC / 72))
    draw.line(pts + [pts[0]], fill=GOLD, width=stroke, joint="curve")

    draw_wordmark(
        draw, canvas_w=W,
        cy=int(H * WORDMARK_CY_FRAC),
        size_px=WORDMARK_PX,
        bg=BG,
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, format="PNG")
    print(f"✓ wrote {OUT.relative_to(ROOT)} ({W}×{H})")


if __name__ == "__main__":
    main()
