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
WORDMARK_FONT_INDEX = 0      # Helvetica Neue Regular — ~30% heavier stem than Light
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
                  size_px: int, fill=WHITE, bg=None,
                  tracking_frac: float = WORDMARK_TRACKING_FRAC):
    """Draw the BARREL wordmark centered on (canvas_w/2, cy).

    Passing `bg` (icon background color) knocks the horizontal crossbar out
    of the 'A' with a bg-colored rectangle — brand spec: A has no crossbar.
    """
    font = _load_font(size_px)
    letters = "BARREL"
    tracking = int(size_px * tracking_frac)
    bboxes = [draw.textbbox((0, 0), ch, font=font) for ch in letters]
    widths = [b[2] - b[0] for b in bboxes]
    total = sum(widths) + tracking * (len(letters) - 1)
    x = (canvas_w - total) // 2
    ascent, descent = font.getmetrics()
    cap_h = ascent - descent // 2   # rough cap height for a mostly-capital run
    baseline_y = cy + (ascent - descent) // 2 - descent
    for i, (ch, w) in enumerate(zip(letters, widths)):
        draw.text((x, baseline_y), ch, font=font, fill=fill, anchor="ls")
        if ch == "A" and bg is not None:
            # Knock out the crossbar. The crossbar on Helvetica Neue's 'A'
            # sits about 40% of the cap height above the baseline; widened
            # knockout to cover the heavier Regular-weight stroke.
            bar_y_center = baseline_y - int(cap_h * 0.42)
            half_thick = max(3, int(cap_h * 0.085))
            bar_y1 = bar_y_center - half_thick
            bar_y2 = bar_y_center + half_thick
            bar_x1 = x + int(w * 0.16)
            bar_x2 = x + int(w * 0.84)
            draw.rectangle((bar_x1, bar_y1, bar_x2, bar_y2), fill=bg)
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

    # BARREL wordmark (bg=BG erases the A's crossbar)
    draw_wordmark(draw, canvas_w=ICON_SIZE,
                  cy=int(ICON_SIZE * WORDMARK_CY_FRAC),
                  size_px=WORDMARK_PX, bg=BG)

    ICON_PATH.parent.mkdir(parents=True, exist_ok=True)
    img.save(ICON_PATH, format="PNG")
    print(f"✓ wrote {ICON_PATH} ({ICON_SIZE}×{ICON_SIZE})")


if __name__ == "__main__":
    main()
