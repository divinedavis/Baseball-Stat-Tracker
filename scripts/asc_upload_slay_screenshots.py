#!/usr/bin/env python3
"""Replace App Store screenshots for the editable version with the
Slay-style set in docs/marketing/slay_65/.

Idempotent: deletes the existing 6.5" Display screenshot set and uploads
the new five panels in order (01 → 05). Re-runnable; output is the final
state.

If you also want a 6.9" Display set published alongside, this script
uploads docs/marketing/slay/*.png there too.
"""
from __future__ import annotations

import hashlib
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_publish_metadata import (  # type: ignore
    CONFIG, api, create_screenshot_set, delete_screenshot_set,
    find_localization, list_screenshot_sets,
    list_screenshots_in_set, load_env, make_token, require, upload_screenshot,
)

EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
    "METADATA_REJECTED", "WAITING_FOR_REVIEW", "INVALID_BINARY",
    "READY_FOR_REVIEW", "DEVELOPER_REMOVED_FROM_SALE",
}


def find_or_create_editable_version(app_id: str, token: str, target_version: str) -> dict:
    """Pick the highest-numbered version in an editable state. If there is
    none, create one at `target_version`."""
    status, d = api("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=20", token)
    require(status, d, "list versions")
    for v in sorted(d.get("data", []),
                    key=lambda v: v["attributes"].get("versionString", "0"),
                    reverse=True):
        if v["attributes"].get("appStoreState") in EDITABLE_STATES:
            return v
    print(f"  no editable version found — creating {target_version}")
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": target_version,
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
            },
        }
    }
    status, d = api("POST", "/v1/appStoreVersions", token, body)
    require(status, d, f"create version {target_version}")
    return d["data"]


def find_or_create_localization(version_id: str, token: str, locale: str = "en-US") -> dict:
    """Get the locale's localization, creating it if the new version came
    up empty (Apple usually copies forward, but not always)."""
    status, d = api("GET",
                    f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
                    token)
    require(status, d, "list localizations")
    for loc in d.get("data", []):
        if loc["attributes"].get("locale") == locale:
            return loc
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": locale},
            "relationships": {
                "appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": version_id}
                }
            },
        }
    }
    status, d = api("POST", "/v1/appStoreVersionLocalizations", token, body)
    require(status, d, f"create {locale} localization")
    return d["data"]

ROOT = Path(__file__).resolve().parent.parent
SLAY_69 = ROOT / "docs" / "marketing" / "slay"
SLAY_65 = ROOT / "docs" / "marketing" / "slay_65"

DISPLAY_TYPES = [
    ("APP_IPHONE_67", SLAY_69),  # 1290×2796 — covers 6.5" / 6.7" / 6.9"
    ("APP_IPHONE_65", SLAY_65),  # 1284×2778
]


def replace_set(loc_id: str, display_type: str, src_dir: Path, token: str):
    if not src_dir.exists():
        print(f"  skipping {display_type}: {src_dir} not found")
        return
    pngs = sorted(src_dir.glob("*.png"))
    if not pngs:
        print(f"  skipping {display_type}: no PNGs in {src_dir}")
        return

    sets = list_screenshot_sets(loc_id, token)
    for s in sets:
        if s["attributes"].get("screenshotDisplayType") == display_type:
            old_id = s["id"]
            print(f"  ▸ deleting existing {display_type} set ({old_id})")
            delete_screenshot_set(old_id, token)

    new_set = create_screenshot_set(loc_id, display_type, token)
    print(f"  ▸ created {display_type} set ({new_set})")
    for png in pngs:
        upload_screenshot(new_set, png, token)
        print(f"    + uploaded {png.name}")


def main():
    if not CONFIG.exists():
        raise SystemExit(f"missing {CONFIG}")
    env = load_env(CONFIG)
    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])
    app_id = env["ASC_APP_ID"]

    version = find_or_create_editable_version(app_id, token, target_version="1.2")
    print(f"▸ editable version {version['attributes'].get('versionString')} "
          f"({version['attributes'].get('appStoreState')})")
    loc = find_or_create_localization(version["id"], token)
    print(f"▸ en-US localization {loc['id']}")

    for display_type, src in DISPLAY_TYPES:
        print(f"\n▸ {display_type}")
        replace_set(loc["id"], display_type, src, token)

    print("\n✓ done")


if __name__ == "__main__":
    main()
