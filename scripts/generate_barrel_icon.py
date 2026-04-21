#!/usr/bin/env python3
"""Primary BARREL app icon: near-black canvas, gold two-cap barrel, tilted,
with "BARREL" wordmark centered below the logo.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from barrel_geometry import build_barrel_polygon

ROOT = Path(__file__).resolve().parent.parent
ICON_PATH = ROOT / "BaseballStatTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

ICON_SIZE = 1024
BG = (10, 10, 12, 255)
GOLD = (212, 175, 55, 255)
WHITE = (255, 255, 255, 255)

SHAPE_W_FRAC = 0.46          # barrel width as fraction of canvas (30% shorter than prior 0.66)
STROKE_FRAC = 1 / 72
BARREL_CY_FRAC = 0.38        # vertical center of the barrel
WORDMARK_CY_FRAC = 0.74      # vertical center of the BARREL wordmark
WORDMARK_FONT = "/System/Library/Fonts/HelveticaNeue.ttc"
WORDMARK_FONT_INDEX = 7      # Helvetica Neue Light — matches the thin reference stroke
WORDMARK_PX = 112            # size at 1024 canvas (tuned to match reference width)
WORDMARK_TRACKING_FRAC = 0.32  # wide letter spacing to match the reference spacing


def _load_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate, index in (
        (WORDMARK_FONT, WORDMARK_FONT_INDEX),
        (WORDMARK_FONT, 0),
        ("/System/Library/Fonts/Helvetica.ttc", 0),
        ("/System/Library/Fonts/SFNS.ttf", 0),
    ):
        try:
            return ImageFont.truetype(candidate, size=size, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_wordmark(draw: ImageDraw.ImageDraw, canvas_w: int, cy: int,
                  size_px: int, fill=WHITE, tracking_frac: float = WORDMARK_TRACKING_FRAC):
    font = _load_font(size_px)
    letters = "BARREL"
    tracking = int(size_px * tracking_frac)
    bboxes = [draw.textbbox((0, 0), ch, font=font) for ch in letters]
    widths = [b[2] - b[0] for b in bboxes]
    total = sum(widths) + tracking * (len(letters) - 1)
    x = (canvas_w - total) // 2
    # Vertically center each letter around cy using the tallest glyph's bbox
    ascent_descent = max(b[3] - b[1] for b in bboxes)
    top_y = cy - ascent_descent // 2
    for i, (ch, w) in enumerate(zip(letters, widths)):
        # textbbox y offset compensation so all letters sit on a common baseline
        offset_y = -bboxes[i][1]
        draw.text((x, top_y + offset_y - ascent_descent // 2 + ascent_descent),
                  ch, font=font, fill=fill, anchor="ls")
        x += w + tracking


def main():
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), BG)
    draw = ImageDraw.Draw(img)

    # Barrel mark — draw the closed outline with a rounded joint so the
    # polygon-approximated arc edges stay smooth under a thick stroke.
    pts = build_barrel_polygon(
        center_x=ICON_SIZE / 2,
        center_y=ICON_SIZE * BARREL_CY_FRAC,
        shape_w=ICON_SIZE * SHAPE_W_FRAC,
    )
    stroke = max(3, int(ICON_SIZE * STROKE_FRAC))
    draw.line(pts + [pts[0]], fill=GOLD, width=stroke, joint="curve")

    # BARREL wordmark
    draw_wordmark(draw, canvas_w=ICON_SIZE,
                  cy=int(ICON_SIZE * WORDMARK_CY_FRAC),
                  size_px=WORDMARK_PX)

    ICON_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(ICON_PATH, format="PNG")
    print(f"✓ wrote {ICON_PATH} ({ICON_SIZE}×{ICON_SIZE})")


if __name__ == "__main__":
    main()
