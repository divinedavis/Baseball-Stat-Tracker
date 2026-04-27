#!/usr/bin/env python3
"""Compose Spanish (es-MX) App Store screenshots from the localized simulator captures.

Reads docs/marketing/raw_es/*.png (1320x2868), overlays the BARREL wordmark + a
Spanish headline + subtitle, and writes 6.9 and 6.5 inch variants to
docs/marketing/6.9_es and docs/marketing/6.5_es.

Reuses the layout helpers from compose_marketing.py — only the SCREENS table
and IO paths differ.
"""
from __future__ import annotations

import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from compose_marketing import compose_frame, ROOT  # noqa: E402

RAW = ROOT / "docs" / "marketing" / "raw_es"
OUT_69 = ROOT / "docs" / "marketing" / "6.9_es"
OUT_65 = ROOT / "docs" / "marketing" / "6.5_es"
OUT_69.mkdir(parents=True, exist_ok=True)
OUT_65.mkdir(parents=True, exist_ok=True)

# Mirrors SCREENS in compose_marketing.py — same filenames, Spanish copy.
SCREENS = [
    ("01_roster.png",         "Tu alineación.",            "Encuentra el punto perfecto."),
    ("02_detail_top.png",     "Cada turno al bate.",       "Entrena para el impacto."),
    ("03_expanded_stats.png", "Cada número.",              "Hecho para la potencia."),
    ("04_game_log.png",       "Cada juego guardado.",      "Registra. Mejora. Domina."),
]


def main() -> None:
    from PIL import Image
    for raw_name, headline, subtitle in SCREENS:
        raw_path = RAW / raw_name
        if not raw_path.exists():
            print(f"skip {raw_name} (missing in {RAW})")
            continue
        frame = compose_frame(raw_path, headline, subtitle)
        out_69 = OUT_69 / raw_name
        frame.convert("RGB").save(out_69, "PNG", optimize=True)
        out_65 = OUT_65 / raw_name
        frame_65 = frame.resize((1284, 2778), Image.LANCZOS)
        frame_65.convert("RGB").save(out_65, "PNG", optimize=True)
        print(f"wrote {out_69.relative_to(ROOT)} and 6.5_es/ variant")


if __name__ == "__main__":
    main()
