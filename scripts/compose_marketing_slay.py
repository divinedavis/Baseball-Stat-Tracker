#!/usr/bin/env python3
"""Slay-style App Store screenshots for Barrel.

Five 1320×2868 panels (iPhone 6.9" Display) on a lavender canvas, each
with:
  - Small dark "tag" pill at top
  - Big chunky white headline (Bagel Fat One)
  - Tilted phone mockup holding a real-app screenshot (or, for panel 5,
    a synthesized AI-chat scene)
  - 2–3 floating sticker chips with subtle rotation + drop shadow
  - 1–2 emoji decorations

Outputs land at docs/marketing/slay/<n>_<slug>.png
"""
from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "marketing" / "raw"
OUT = ROOT / "docs" / "marketing" / "slay"
OUT_65 = ROOT / "docs" / "marketing" / "slay_65"
FONTS = ROOT / "docs" / "marketing" / "fonts"
OUT.mkdir(parents=True, exist_ok=True)
OUT_65.mkdir(parents=True, exist_ok=True)

W, H = 1290, 2796  # APP_IPHONE_67 — covers iPhone 14/15/16/17 Pro Max
BG = (135, 145, 250, 255)            # lavender / periwinkle blue
WHITE = (255, 255, 255, 255)
BLACK = (15, 15, 18, 255)
INK = (24, 24, 28, 255)
SHADOW = (0, 0, 0, 90)

DISPLAY = str(FONTS / "BagelFatOne-Regular.ttf")
EMOJI = "/System/Library/Fonts/Apple Color Emoji.ttc"


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(DISPLAY, size)


def emoji_font() -> ImageFont.FreeTypeFont:
    # Apple Color Emoji is a bitmap font with fixed strikes;
    # 160 is the largest one PIL accepts. We scale down to the requested
    # display size with high-quality resampling.
    return ImageFont.truetype(EMOJI, 160)


# ---------- primitives ----------

def rounded_rect(size, radius, fill, stroke=None, stroke_w=0):
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=fill,
                        outline=stroke, width=stroke_w)
    return img


def drop_shadow(layer: Image.Image, offset=(0, 14), blur=22, opacity=110) -> Image.Image:
    base_w, base_h = layer.size
    pad = blur * 3 + max(abs(offset[0]), abs(offset[1]))
    canvas = Image.new("RGBA", (base_w + 2 * pad, base_h + 2 * pad), (0, 0, 0, 0))
    alpha = layer.split()[-1]
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda a: int(a * opacity / 255)))
    canvas.alpha_composite(shadow, (pad + offset[0], pad + offset[1]))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(layer, (pad, pad))
    return canvas


def rotated(layer: Image.Image, degrees: float) -> Image.Image:
    return layer.rotate(degrees, resample=Image.BICUBIC, expand=True)


def text_layer(text: str, size: int, color=BLACK,
               line_spacing: float = 0.92,
               align="left") -> Image.Image:
    f = font(size)
    lines = text.split("\n")
    widths, heights = [], []
    for line in lines:
        bbox = f.getbbox(line)
        widths.append(bbox[2] - bbox[0])
        heights.append(int(size * line_spacing))
    total_w = max(widths) + 16
    total_h = sum(heights) + 16
    img = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    y = 8
    for line, lw, lh in zip(lines, widths, heights):
        if align == "center":
            x = (total_w - lw) // 2
        elif align == "right":
            x = total_w - lw - 8
        else:
            x = 8
        d.text((x, y), line, font=f, fill=color)
        y += lh
    return img


def text_size(text: str, size: int):
    f = font(size)
    bbox = f.getbbox(text)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


# ---------- composite parts ----------

def tag_pill(text: str, size_pt: int = 38) -> Image.Image:
    tw, th = text_size(text, size_pt)
    pad_x, pad_y = 36, 14
    pill = rounded_rect((tw + pad_x * 2, th + pad_y * 2 + 8), radius=999, fill=BLACK)
    inner = text_layer(text, size_pt, color=WHITE, align="center")
    pill.alpha_composite(
        inner,
        ((pill.width - inner.width) // 2, (pill.height - inner.height) // 2),
    )
    return pill


def sticker(text: str, size_pt: int = 44, rotation: float = -6) -> Image.Image:
    tw, th = text_size(text, size_pt)
    pad_x, pad_y = 30, 14
    chip = rounded_rect((tw + pad_x * 2, th + pad_y * 2 + 8), radius=999, fill=WHITE)
    inner = text_layer(text, size_pt, color=BLACK, align="center")
    chip.alpha_composite(
        inner,
        ((chip.width - inner.width) // 2, (chip.height - inner.height) // 2),
    )
    chip = drop_shadow(chip, offset=(0, 10), blur=14, opacity=80)
    return rotated(chip, rotation)


def emoji_layer(char: str, size_pt: int) -> Image.Image:
    """Render a single emoji at `size_pt`. Uses Apple Color Emoji at its
    fixed 160pt strike and resizes to the target with high-quality LANCZOS."""
    f = emoji_font()
    canvas = Image.new("RGBA", (220, 220), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    d.text((0, 0), char, font=f, embedded_color=True)
    bbox = canvas.getbbox()
    if bbox:
        canvas = canvas.crop(bbox)
    if size_pt != 160:
        ratio = size_pt / 160
        new_size = (max(1, int(canvas.width * ratio)), max(1, int(canvas.height * ratio)))
        canvas = canvas.resize(new_size, Image.LANCZOS)
    return canvas


def phone_mockup(screenshot_path: Path | None,
                  width: int = 920,
                  rotation: float = -3.5) -> Image.Image:
    """Returns a phone-shaped layer with the screenshot inside, rotated and shadowed."""
    aspect = 19.5 / 9  # iPhone aspect
    p_w = width
    p_h = int(p_w * aspect)
    bezel = 18
    # Body: black rounded rect
    body = rounded_rect((p_w, p_h), radius=98, fill=BLACK)
    if screenshot_path and screenshot_path.exists():
        shot = Image.open(screenshot_path).convert("RGBA")
        # Resize shot to fill the inner area
        inner_w = p_w - bezel * 2
        inner_h = p_h - bezel * 2
        shot_ratio = shot.width / shot.height
        inner_ratio = inner_w / inner_h
        if shot_ratio > inner_ratio:
            new_h = inner_h
            new_w = int(new_h * shot_ratio)
        else:
            new_w = inner_w
            new_h = int(new_w / shot_ratio)
        shot = shot.resize((new_w, new_h), Image.LANCZOS)
        # Center crop
        sx = (shot.width - inner_w) // 2
        sy = (shot.height - inner_h) // 2
        shot = shot.crop((sx, sy, sx + inner_w, sy + inner_h))
        # Mask with rounded corners to fit inside the bezel curve
        mask = Image.new("L", (inner_w, inner_h), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner_w - 1, inner_h - 1),
                                                radius=80, fill=255)
        body.paste(shot, (bezel, bezel), mask)
    body = drop_shadow(body, offset=(0, 28), blur=46, opacity=120)
    return rotated(body, rotation)


def synth_ai_phone(width: int = 920, rotation: float = -3.5) -> Image.Image:
    """Synthesizes a 'Barrel AI Coach' chat scene since we don't have a
    pre-captured screenshot of the live AI tab."""
    aspect = 19.5 / 9
    p_w = width
    p_h = int(p_w * aspect)
    bezel = 18
    inner_w = p_w - bezel * 2
    inner_h = p_h - bezel * 2

    # Inner phone screen (light)
    screen = Image.new("RGBA", (inner_w, inner_h), (252, 252, 254, 255))
    d = ImageDraw.Draw(screen)

    # Top safe area + status bar text
    bar = font(34)
    d.text((40, 50), "9:41", font=bar, fill=BLACK)
    # Title
    title_f = font(64)
    title_t = "AI Coach"
    tw = title_f.getbbox(title_t)[2]
    d.text(((inner_w - tw) // 2, 130), title_t, font=title_f, fill=BLACK)
    # Tier pill
    tier = tag_pill("Pro", size_pt=24)
    screen.alpha_composite(tier, (inner_w - tier.width - 40, 140))

    # Chat bubbles
    bubble_font = font(46)
    user_msg = "How do I keep my hands inside on inside fastballs?"
    user_lines = wrap_text(user_msg, bubble_font, inner_w - 220)
    user_h = 50 + len(user_lines) * 60 + 50
    user_w = inner_w - 200
    user_bubble = rounded_rect((user_w, user_h), radius=44,
                               fill=(60, 110, 255, 255))
    ud = ImageDraw.Draw(user_bubble)
    yy = 36
    for line in user_lines:
        ud.text((40, yy), line, font=bubble_font, fill=WHITE)
        yy += 60
    screen.alpha_composite(user_bubble, (180, 360))

    # Assistant bubble
    asst_msg = "Lead with your knob, not your barrel.\nTwo-tee drill, 5 reps."
    asst_lines = []
    for raw in asst_msg.split("\n"):
        asst_lines.extend(wrap_text(raw, bubble_font, inner_w - 220))
    asst_h = 50 + len(asst_lines) * 60 + 50
    asst_w = inner_w - 200
    asst_bubble = rounded_rect((asst_w, asst_h), radius=44,
                               fill=(232, 232, 240, 255))
    ad = ImageDraw.Draw(asst_bubble)
    yy = 36
    for line in asst_lines:
        ad.text((40, yy), line, font=bubble_font, fill=BLACK)
        yy += 60
    screen.alpha_composite(asst_bubble, (40, 360 + user_h + 28))

    # Composer at bottom
    comp_h = 140
    composer_y = inner_h - comp_h - 30
    comp = rounded_rect((inner_w - 80, comp_h), radius=46,
                        fill=(238, 238, 244, 255))
    cd = ImageDraw.Draw(comp)
    cd.ellipse((28, 30, 28 + 80, 30 + 80), outline=(120, 120, 130), width=4)
    cd.text((48, 50), "@", font=font(42), fill=(120, 120, 130))
    cd.text((150, 38), "Message", font=font(40), fill=(140, 140, 150))
    # Send button
    btn = rounded_rect((96, 96), radius=999, fill=(60, 110, 255, 255))
    bd = ImageDraw.Draw(btn)
    bd.polygon([(38, 56), (60, 30), (60, 46), (78, 46), (78, 66), (60, 66), (60, 82)],
               fill=WHITE)
    comp.alpha_composite(btn, (comp.width - 130, 22))
    screen.alpha_composite(comp, (40, composer_y))

    # Compose into phone body
    body = rounded_rect((p_w, p_h), radius=98, fill=BLACK)
    mask = Image.new("L", (inner_w, inner_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner_w - 1, inner_h - 1),
                                            radius=80, fill=255)
    body.paste(screen, (bezel, bezel), mask)
    body = drop_shadow(body, offset=(0, 28), blur=46, opacity=120)
    return rotated(body, rotation)


def wrap_text(text: str, f: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if f.getbbox(trial)[2] <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


# ---------- panels ----------

PANELS = [
    {
        "slug": "tap",
        "tag": "Tap it",
        "headline": "One tap.\nEvery at-bat.",
        "screenshot": "02_detail_top.png",
        "stickers": [("+1B", -8, (160, 1340)),
                     ("+HR", 9, (1080, 1500)),
                     ("Strong", -4, (140, 1880))],
        "emojis": [("⚾", 220, (1010, 1900)), ("🔥", 180, (130, 1180))],
    },
    {
        "slug": "stats",
        "tag": "See it",
        "headline": "Slash line,\nlive as you play.",
        "screenshot": "03_expanded_stats.png",
        "stickers": [(".750", -7, (130, 1320)),
                     ("OPS 1.250", 8, (980, 1480)),
                     ("Hot streak", -3, (180, 2050))],
        "emojis": [("📈", 200, (1050, 1320)), ("🔥", 180, (130, 1900))],
    },
    {
        "slug": "log",
        "tag": "Log it",
        "headline": "Every game,\nkept.",
        "screenshot": "04_game_log.png",
        "stickers": [("Tue Apr 21", -6, (140, 1340)),
                     ("3 AB", 7, (1090, 1480)),
                     ("1.000", -4, (130, 2030))],
        "emojis": [("📒", 200, (1040, 1340)), ("⚾", 180, (160, 1800))],
    },
    {
        "slug": "roster",
        "tag": "Lineup",
        "headline": "Every player.\nEvery stat.",
        "screenshot": "01_roster.png",
        "stickers": [("Jordan #7", -8, (140, 1340)),
                     ("Micah #12", 9, (1010, 1490)),
                     ("Ari #3", -4, (180, 2010))],
        "emojis": [("🧢", 200, (1040, 1320)), ("⚡", 180, (140, 1880))],
    },
    {
        "slug": "ai",
        "tag": "Ask Barrel",
        "headline": "Coach in\nyour pocket.",
        "screenshot": None,  # synth
        "stickers": [("Frame-by-frame", -7, (110, 1320)),
                     ("Drills", 9, (1080, 1500)),
                     ("Real game data", -4, (140, 2050))],
        "emojis": [("✨", 200, (1040, 1320)), ("⚾", 180, (140, 1880))],
    },
]


def compose_panel(p: dict, idx: int) -> Path:
    canvas = Image.new("RGBA", (W, H), BG)

    # ---- Tag pill (top) ----
    tag = tag_pill(p["tag"], size_pt=42)
    canvas.alpha_composite(tag, ((W - tag.width) // 2, 220))

    # ---- Headline ----
    headline_layer = text_layer(p["headline"], 144, color=WHITE,
                                line_spacing=1.05, align="center")
    canvas.alpha_composite(headline_layer,
                           ((W - headline_layer.width) // 2, 320))

    # ---- Phone mockup ----
    if p["screenshot"]:
        phone = phone_mockup(RAW / p["screenshot"], width=860, rotation=-3.5)
    else:
        phone = synth_ai_phone(width=860, rotation=-3.5)
    px = (W - phone.width) // 2
    py = 760
    canvas.alpha_composite(phone, (px, py))

    # ---- Sticker chips ----
    for text, rot, (x, y) in p["stickers"]:
        chip = sticker(text, size_pt=46, rotation=rot)
        canvas.alpha_composite(chip, (x, y))

    # ---- Emojis ----
    for char, sz, (x, y) in p["emojis"]:
        em = emoji_layer(char, size_pt=sz)
        canvas.alpha_composite(em, (x, y))

    out_path = OUT / f"{idx + 1:02d}_{p['slug']}.png"
    rgb = canvas.convert("RGB")
    rgb.save(out_path, "PNG", optimize=True)
    # Down-resample to 6.5" Display (1284×2778) for ASC's existing slot
    out_65 = OUT_65 / f"{idx + 1:02d}_{p['slug']}.png"
    rgb.resize((1284, 2778), Image.LANCZOS).save(out_65, "PNG", optimize=True)
    return out_path


def main():
    for i, panel in enumerate(PANELS):
        path = compose_panel(panel, i)
        print(f"  ✓ {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
