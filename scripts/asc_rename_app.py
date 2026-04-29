#!/usr/bin/env python3
"""Rename the App Store listing name across all locales.

PATCHes only the `name` field on each appInfoLocalization, leaving subtitle
and other metadata untouched. Idempotent — re-running with the same name is a no-op.

Usage:
    scripts/asc_rename_app.py --dry-run          # show planned changes
    scripts/asc_rename_app.py                    # apply (default name: "Barrel Trac")
    scripts/asc_rename_app.py --name "Foo Bar"   # custom name
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from asc_publish_es_metadata import (  # noqa: E402
    CONFIG, api, find_editable_app_info, load_env, make_token, require,
)

DEFAULT_NAME = "Barrel Trac"
LOCALES = ["en-US", "es-MX"]


def find_app_info_localization(app_info_id: str, locale: str, token: str) -> dict | None:
    status, d = api("GET", f"/v1/appInfos/{app_info_id}/appInfoLocalizations", token)
    require(status, d, "list app info localizations")
    for loc in d.get("data", []):
        if loc["attributes"].get("locale") == locale:
            return loc
    return None


def patch_name(loc_id: str, locale: str, name: str, token: str, dry: bool) -> None:
    body = {
        "data": {
            "type": "appInfoLocalizations",
            "id": loc_id,
            "attributes": {"name": name},
        }
    }
    if dry:
        print(f"  [dry] would PATCH {locale} app info localization {loc_id}: name={name!r} ({len(name)} chars)")
        return
    status, d = api("PATCH", f"/v1/appInfoLocalizations/{loc_id}", token, body)
    require(status, d, f"patch {locale} app info localization name")
    print(f"  ✓ {locale} renamed to {name!r}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--name", default=DEFAULT_NAME, help=f"new app name (default: {DEFAULT_NAME!r})")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    if len(args.name) > 30:
        raise SystemExit(f"name too long ({len(args.name)} chars, 30 max)")

    env = load_env(CONFIG)
    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])
    app_id = env["ASC_APP_ID"]

    print(f"▸ renaming app {app_id} to {args.name!r} across {LOCALES}")
    if args.dry_run:
        print("▸ DRY RUN — no writes")
    print()

    info = find_editable_app_info(app_id, token)
    info_id = info["id"]
    print(f"  app info {info_id} state={info['attributes'].get('appStoreState')}")

    for locale in LOCALES:
        loc = find_app_info_localization(info_id, locale, token)
        if loc is None:
            print(f"  ⚠ no {locale} localization found — skipping (create it first)")
            continue
        current_name = loc["attributes"].get("name")
        if current_name == args.name:
            print(f"  · {locale} already named {args.name!r} — skipping")
            continue
        print(f"  {locale}: {current_name!r} → {args.name!r}")
        patch_name(loc["id"], locale, args.name, token, args.dry_run)

    print()
    print("✓ done")


if __name__ == "__main__":
    main()
