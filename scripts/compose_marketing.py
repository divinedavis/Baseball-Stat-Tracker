#!/usr/bin/env python3
"""Composite App Store marketing screenshots from raw simulator captures.

Input:  docs/marketing/raw/*.png  (1320x2868 PNG from xcrun simctl)
Output: docs/marketing/6.9/*.png  (1320x2868 with wordmark + headline)
        docs/marketing/6.5/*.png  (1284x2778 resized)

BARREL brand palette:
  - Canvas near-black (#0A0A0C)
  - Headline white (Georgia Bold Italic)
  - Subtitle gold (#D4AF37)
  - BARREL wordmark + barrel mark centered at top of each frame
"""
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from barrel_geometry import build_barrel_polygon

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "marketing" / "raw"
OUT_69 = ROOT / "docs" / "marketing" / "6.9"
OUT_65 = ROOT / "docs" / "marketing" / "6.5"
OUT_69.mkdir(parents=True, exist_ok=True)
OUT_65.mkdir(parents=True, exist_ok=True)

# 6.9" App Store required pixel size (iPhone 17 Pro Max, 16 Pro Max)
W, H = 1320, 2868

BG = (10, 10, 12, 255)              # near-black canvas #0A0A0C
CARD = (22, 22, 24, 255)            # slightly-lifted inner card
HEADLINE = (255, 255, 255, 255)     # pure white
SUBTITLE = (212, 175, 55, 255)      # BARREL gold #D4AF37
GOLD = (212, 175, 55, 255)
SHADOW = (0, 0, 0, 200)

HEAD_FONT = "/System/Library/Fonts/Supplemental/Georgia Bold Italic.ttf"
SUB_FONT = "/System/Library/Fonts/SFNS.ttf"
WORDMARK_FONT = "/System/Library/Fonts/HelveticaNeue.ttc"

SCREENS = [
    ("01_roster.png",         "Your lineup.",       "Find the sweet spot."),
    ("02_detail_top.png",     "One tap at-bats.",   "Train for impact."),
    ("03_expanded_stats.png", "Every number.",      "Built for power."),
    ("04_game_log.png",       "Every game kept.",   "Track. Improve. Dominate."),
]


def load_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(path, size=size)
    except OSError:
        return ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size=size)


def wrap_center(draw, text, font, canvas_w, top, fill, line_gap=0):
    y = top
    for line in text.split("\n"):
        bbox = draw.textbbox((0, 0), line, font=font)
        line_w = bbox[2] - bbox[0]
        line_h = bbox[3] - bbox[1]
        draw.text(((canvas_w - line_w) / 2, y - bbox[1]), line, font=font, fill=fill)
        y += line_h + line_gap
    return y


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return m


def draw_barrel_mark(draw: ImageDraw.ImageDraw, cx: int, cy: int, width: int, stroke: int = 5):
    """Draw a small gold barrel outline centered at (cx, cy), spanning `width`."""
    pts = build_barrel_polygon(center_x=cx, center_y=cy, shape_w=width)
    draw.polygon(pts, outline=GOLD, fill=None, width=stroke)


def draw_wordmark(draw: ImageDraw.ImageDraw, top: int):
    """BARREL wordmark with the barrel mark to the right."""
    font = load_font(WORDMARK_FONT, 72)
    text = "BARREL"
    bbox = draw.textbbox((0, 0), text, font=font, stroke_width=0)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    mark_w = 140
    gap = 30
    total_w = text_w + gap + mark_w

    x = (W - total_w) // 2
    # Draw BARREL in white with wide letter spacing. The 'A' gets its
    # horizontal crossbar knocked out so the letter reads as an open peak.
    letter_spacing = 8
    cursor = x
    ascent, descent = font.getmetrics()
    cap_h = ascent - descent // 2
    baseline_y = top + ascent
    for ch in text:
        draw.text((cursor, top), ch, font=font, fill=(255, 255, 255, 255))
        cb = draw.textbbox((0, 0), ch, font=font)
        ch_w = cb[2] - cb[0]
        if ch == "A":
            bar_y_center = baseline_y - int(cap_h * 0.42)
            half_thick = max(2, int(cap_h * 0.085))
            draw.rectangle(
                (cursor + int(ch_w * 0.16), bar_y_center - half_thick,
                 cursor + int(ch_w * 0.84), bar_y_center + half_thick),
                fill=BG,
            )
        cursor += ch_w + letter_spacing

    mark_cx = cursor + gap + mark_w // 2 - letter_spacing
    mark_cy = top + text_h // 2 + 6
    draw_barrel_mark(draw, mark_cx, mark_cy, mark_w, stroke=5)


def compose_frame(raw_path: Path, headline: str, subtitle: str) -> Image.Image:
    canvas = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(canvas)

    # Wordmark at very top
    draw_wordmark(d, top=80)

    # Dark rounded inner card
    card_pad = 40
    card_top = 230
    card_bottom = H - 120
    d.rounded_rectangle(
        (card_pad, card_top, W - card_pad, card_bottom),
        radius=72, fill=CARD,
    )

    # Headline — auto-fit longest line to card width
    max_text_w = (W - 2 * card_pad) - 160
    head_size = 220
    while head_size > 90:
        head_font = load_font(HEAD_FONT, head_size)
        widest = max(d.textbbox((0, 0), line, font=head_font)[2] for line in headline.split("\n"))
        if widest <= max_text_w:
            break
        head_size -= 6
    head_y = card_top + 130
    head_bottom = wrap_center(d, headline, head_font, W, head_y, HEADLINE, line_gap=-10)

    # Subtitle in gold
    sub_font = load_font(SUB_FONT, 68)
    sub_y = head_bottom + 50
    sub_bottom = wrap_center(d, subtitle, sub_font, W, sub_y, SUBTITLE, line_gap=14)

    # Phone screenshot
    shot = Image.open(raw_path).convert("RGBA")
    target_w = int(W * 0.78)
    target_h = int(target_w * shot.height / shot.width)
    shot = shot.resize((target_w, target_h), Image.LANCZOS)
    shot.putalpha(rounded_mask(shot.size, radius=88))

    # Drop shadow
    shadow = Image.new("RGBA", (target_w + 120, target_h + 120), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((60, 80, target_w + 60, target_h + 60), radius=88, fill=SHADOW)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=38))

    available = card_bottom - sub_bottom - 100
    phone_y = sub_bottom + 100 + max(0, (available - target_h) // 2)
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
