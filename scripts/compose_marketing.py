#!/usr/bin/env python3
"""Composite App Store marketing screenshots from raw simulator captures.

Input:  docs/marketing/raw/*.png  (1320x2868 PNG from xcrun simctl)
Output: docs/marketing/6.9/*.png  (1320x2868 with headline + subtitle)
        docs/marketing/6.5/*.png  (1284x2778 resized)

Style is inspired by the "Explore" marketing frame:
  - Deep charcoal background
  - Large white headline at top
  - Lighter subtitle below
  - Phone screenshot centered, rounded corners
"""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "marketing" / "raw"
OUT_69 = ROOT / "docs" / "marketing" / "6.9"
OUT_65 = ROOT / "docs" / "marketing" / "6.5"
OUT_69.mkdir(parents=True, exist_ok=True)
OUT_65.mkdir(parents=True, exist_ok=True)

# 6.9" App Store required pixel size (iPhone 17 Pro Max, 16 Pro Max)
W, H = 1320, 2868

BG = (10, 10, 12, 255)              # near-black canvas
CARD = (26, 26, 28, 255)            # dark rounded container
HEADLINE = (255, 255, 255, 255)     # pure white
SUBTITLE = (235, 235, 240, 255)     # near-white
SHADOW = (0, 0, 0, 180)             # phone dropshadow

HEAD_FONT = "/System/Library/Fonts/Supplemental/Georgia Bold Italic.ttf"
SUB_FONT = "/System/Library/Fonts/SFNS.ttf"

SCREENS = [
    ("01_roster.png",         "Your lineup",       "Every player,\nevery stat, at a glance"),
    ("02_detail_top.png",     "One tap at-bats",   "Log hits, walks, strikeouts\nin a single tap"),
    ("03_expanded_stats.png", "Every number",      "AVG, OBP, SLG, OPS —\nlive as you play"),
    ("04_game_log.png",       "Every game kept",   "Scroll back through\nevery at-bat, every day"),
]


def load_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(path, size=size)
    except OSError:
        return ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size=size)


def wrap_center(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont,
                canvas_w: int, top: int, fill, line_gap: int = 0) -> int:
    """Draw multi-line text centered horizontally. Returns bottom y."""
    y = top
    for line in text.split("\n"):
        bbox = draw.textbbox((0, 0), line, font=font)
        line_w = bbox[2] - bbox[0]
        line_h = bbox[3] - bbox[1]
        draw.text(((canvas_w - line_w) / 2, y - bbox[1]), line, font=font, fill=fill)
        y += line_h + line_gap
    return y


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return m


def compose_frame(raw_path: Path, headline: str, subtitle: str) -> Image.Image:
    canvas = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(canvas)

    # Dark rounded inner card — subtle depth, edge padding 40px
    card_pad = 40
    card_top = 120
    card_bottom = H - 120
    d.rounded_rectangle(
        (card_pad, card_top, W - card_pad, card_bottom),
        radius=72, fill=CARD,
    )

    # Headline — auto-fit longest line to card width (minus inset)
    max_text_w = (W - 2 * card_pad) - 160
    head_size = 220
    while head_size > 90:
        head_font = load_font(HEAD_FONT, head_size)
        widest = max(
            d.textbbox((0, 0), line, font=head_font)[2] for line in headline.split("\n")
        )
        if widest <= max_text_w:
            break
        head_size -= 6
    head_y = card_top + 140
    head_bottom = wrap_center(d, headline, head_font, W, head_y, HEADLINE, line_gap=-10)

    # Subtitle
    sub_font = load_font(SUB_FONT, 76)
    sub_y = head_bottom + 60
    sub_bottom = wrap_center(d, subtitle, sub_font, W, sub_y, SUBTITLE, line_gap=14)

    # Load and size the phone screenshot. Rendered as a phone-shaped rounded rect.
    shot = Image.open(raw_path).convert("RGBA")
    target_w = int(W * 0.78)                  # slightly inset from card
    target_h = int(target_w * shot.height / shot.width)
    shot = shot.resize((target_w, target_h), Image.LANCZOS)

    # Round phone corners
    shot.putalpha(rounded_mask(shot.size, radius=88))

    # Drop-shadow layer
    shadow = Image.new("RGBA", (target_w + 120, target_h + 120), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        (60, 80, target_w + 60, target_h + 60),
        radius=88, fill=SHADOW,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=38))

    # Position phone centered under subtitle, ensuring bottom fits card
    available = card_bottom - sub_bottom - 120
    phone_y = sub_bottom + 120 + max(0, (available - target_h) // 2)
    phone_x = (W - target_w) // 2
    canvas.alpha_composite(shadow, (phone_x - 60, phone_y - 40))
    canvas.alpha_composite(shot, (phone_x, phone_y))

    return canvas


def main() -> None:
    for raw_name, headline, subtitle in SCREENS:
        raw_path = RAW / raw_name
        if not raw_path.exists():
            print(f"skip {raw_name} (missing)")
            continue
        frame = compose_frame(raw_path, headline, subtitle)
        out_69 = OUT_69 / raw_name
        frame.convert("RGB").save(out_69, "PNG", optimize=True)
        out_65 = OUT_65 / raw_name
        frame_65 = frame.resize((1284, 2778), Image.LANCZOS)
        frame_65.convert("RGB").save(out_65, "PNG", optimize=True)
        print(f"wrote {out_69.relative_to(ROOT)} and 6.5/ variant")


if __name__ == "__main__":
    main()
