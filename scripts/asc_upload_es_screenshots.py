#!/usr/bin/env python3
"""Upload Spanish (es-MX) screenshots to the editable App Store Version listing.

Reuses the screenshot machinery from asc_publish_metadata.py and the env/auth
machinery from asc_publish_es_metadata.py. Idempotent: tears down any existing
es-MX screenshot set per display type before re-uploading.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from asc_publish_es_metadata import (  # noqa: E402
    CONFIG, ROOT, api, find_editable_version, load_env, make_token, require,
)
from asc_publish_metadata import (  # noqa: E402
    create_screenshot_set, delete_screenshot_set,
    list_screenshot_sets, upload_screenshot,
)

LOCALE = "es-MX"
DEFAULT_VERSION = "1.1"

# APP_IPHONE_67 covers both 6.7" and 6.9" iPhone Pro Max screenshots; Apple has
# not introduced a separate 6.9" enum yet. 6.5" stays distinct.
SCREENSHOT_FILES = ["01_roster.png", "02_detail_top.png", "03_expanded_stats.png", "04_game_log.png"]
SCREENSHOTS = [
    ("APP_IPHONE_67", ROOT / "docs" / "marketing" / "6.9_es", SCREENSHOT_FILES),
    ("APP_IPHONE_65", ROOT / "docs" / "marketing" / "6.5_es", SCREENSHOT_FILES),
]


def find_localization(version_id: str, token: str) -> dict:
    status, d = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", token)
    require(status, d, "list version localizations")
    for loc in d.get("data", []):
        if loc["attributes"].get("locale") == LOCALE:
            return loc
    raise SystemExit(f"no {LOCALE} localization on version {version_id}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--version", default=DEFAULT_VERSION)
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    env = load_env(CONFIG)
    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])
    app_id = env["ASC_APP_ID"]

    print(f"▸ resolving version {args.version}")
    version = find_editable_version(app_id, args.version, token)
    if version is None:
        raise SystemExit(f"no editable version {args.version} found")
    version_id = version["id"]
    print(f"  version {version_id} state={version['attributes'].get('appStoreState')}")

    loc = find_localization(version_id, token)
    loc_id = loc["id"]
    print(f"  {LOCALE} localization {loc_id}")

    existing = list_screenshot_sets(loc_id, token)
    by_type = {s["attributes"]["screenshotDisplayType"]: s["id"] for s in existing}

    for display_type, folder, filenames in SCREENSHOTS:
        files = [folder / n for n in filenames]
        missing = [f for f in files if not f.exists()]
        if missing:
            raise SystemExit(f"missing screenshot files: {missing}")

        if args.dry_run:
            print(f"  [dry] would replace {display_type} with {[f.name for f in files]}")
            continue

        if display_type in by_type:
            old_id = by_type[display_type]
            print(f"  removing prior {display_type} set {old_id}")
            delete_screenshot_set(old_id, token)

        set_id = create_screenshot_set(loc_id, display_type, token)
        print(f"  created {display_type} set {set_id}")
        for f in files:
            upload_screenshot(set_id, f, token)
            print(f"    ↳ uploaded {f.name} ({f.stat().st_size // 1024} KB)")

    print("✓ done")


if __name__ == "__main__":
    main()
