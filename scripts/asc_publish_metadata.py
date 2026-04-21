#!/usr/bin/env python3
"""Publish App Store Version 1.0 metadata + screenshots via the ASC REST API.

Fills Promotional Text, Description, Keywords, Support/Marketing URL, and
Copyright on the en-US localization of the current "Prepare for Submission"
version. Uploads 4 screenshots each for the 6.9" (APP_IPHONE_69) and 6.5"
(APP_IPHONE_65) display types, replacing any prior set to stay idempotent.

Credentials come from scripts/asc-config.env (same file ship-to-testflight.sh
uses). Re-runnable: existing localization is PATCHed in place, and screenshot
sets are torn down + rebuilt so the final state always matches this script.

Usage:
    scripts/asc_publish_metadata.py                # push everything
    scripts/asc_publish_metadata.py --no-upload    # metadata only, keep old shots
    scripts/asc_publish_metadata.py --dry-run      # show what would change
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import jwt  # PyJWT
except ImportError:
    sys.stderr.write("error: PyJWT not installed. run: pip3 install --user 'pyjwt[crypto]'\n")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "scripts" / "asc-config.env"
API = "https://api.appstoreconnect.apple.com"

LOCALE = "en-US"
VERSION_STRING = "1.0"

COPY = {
    "promotionalText": (
        "Coaches, parents, and players: log every at-bat in one tap. "
        "Live AVG, OBP, SLG, OPS. No account required. Built for the dugout, "
        "fast enough for the bench."
    ),
    "description": (
        "Baseball Stat Tracker is the fastest way to capture a real-game at-bat. "
        "Tap once — the stats update instantly.\n\n"
        "Built for coaches, parents, and players who want real numbers without "
        "wrestling a spreadsheet between innings.\n\n"
        "WHY YOU'LL LIKE IT\n"
        "• One tap per at-bat. 1B, 2B, 3B, HR, BB, K, stolen bases, RBIs — all one press away.\n"
        "• Live slash line. AVG, OBP, SLG, OPS recalculate the moment you log a result.\n"
        "• Counting stats, ready. AB, H, HR, RBI, BB, K, SB, GO, FO, LO — expand the grid when you want the detail.\n"
        "• Contact quality. Tag a hit as strong or weak to keep a read on how the ball came off the bat.\n"
        "• Full game log. Every at-bat is timestamped and grouped by day so you can scroll back through a whole season.\n"
        "• Recent form meter. See the last five at-bats at a glance — streaks and slumps, visible.\n"
        "• Undo and redo anything. Tapped the wrong button mid-inning? One press and it's gone.\n"
        "• Your whole roster. Add every player on the bench — numbers, positions, ages — and flip between them instantly.\n\n"
        "BUILT FOR THE DUGOUT\n"
        "No accounts. No ads. No subscription. Sign in with Apple if you want your session to follow you "
        "across reinstalls, or use a simple email fallback. Everything stays on your device.\n\n"
        "PRIVACY FIRST\n"
        "Baseball Stat Tracker does not collect your data. No analytics. No tracking. Your roster, at-bats, "
        "and game logs are stored locally on your iPhone.\n\n"
        "MADE FOR YOUTH, TRAVEL, AND REC LEAGUES\n"
        "If you are coaching a 9–12 team, tracking your kid's season, or just want to see your own numbers "
        "tick up with every swing — this is the app.\n\n"
        "Download Baseball Stat Tracker and make every at-bat count."
    ),
    "keywords": "baseball,stats,tracker,at-bat,batting,average,coach,softball,youth,dugout,ops,slg,obp,scorebook",
    "supportUrl": "https://github.com/divinedavis/Baseball-Stat-Tracker",
    "marketingUrl": "https://github.com/divinedavis/Baseball-Stat-Tracker",
}

COPYRIGHT = "© 2026 Divine Davis"

# ASC API enum note: `APP_IPHONE_67` covers both 6.7" (1290x2796) and 6.9"
# (1320x2868) iPhone Pro Max screenshots — Apple has not introduced a
# separate `APP_IPHONE_69` enum yet even though the web UI labels the display
# group "iPhone 6.9 Display".
SCREENSHOTS = [
    ("APP_IPHONE_67", ROOT / "docs" / "marketing" / "6.9", ["01_roster.png", "02_detail_top.png", "03_expanded_stats.png", "04_game_log.png"]),
    ("APP_IPHONE_65", ROOT / "docs" / "marketing" / "6.5", ["01_roster.png", "02_detail_top.png", "03_expanded_stats.png", "04_game_log.png"]),
]

# Quirk: app previews use IPHONE_67 / IPHONE_65 (no APP_ prefix) — different
# from the screenshot enum. The 886x1920 H.264 file is accepted for both, so
# we upload the same asset to both sets rather than maintaining two copies.
PREVIEW_FILE = ROOT / "docs" / "marketing" / "preview" / "bst_preview_886x1920.mov"
PREVIEWS = [
    ("IPHONE_67", PREVIEW_FILE),
    ("IPHONE_65", PREVIEW_FILE),
]


def load_env(path: Path) -> dict:
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip().strip('"').strip("'")
        # Expand $VAR / ${VAR} / ~ the way the shell would
        v = os.path.expandvars(os.path.expanduser(v))
        env[k.strip()] = v
    return env


def make_token(key_id: str, issuer: str, key_path: str) -> str:
    with open(os.path.expanduser(key_path)) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def api(method: str, path: str, token: str, body=None, raw_body=None, headers=None, timeout=60):
    url = f"{API}{path}" if path.startswith("/") else path
    if raw_body is not None:
        data = raw_body
        base_headers = {"Authorization": f"Bearer {token}"}
    else:
        data = None if body is None else json.dumps(body).encode()
        base_headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }
    if headers:
        base_headers.update(headers)
    req = urllib.request.Request(url, data=data, method=method, headers=base_headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw and r.headers.get("content-type", "").startswith("application/") else raw)
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")[:6000]
        return e.code, {"error": body_text}


def require(status: int, body, what: str):
    if status >= 300:
        raise SystemExit(f"ASC API error on {what} (status {status}): {body}")
    return body


# ---------- resolve version + localization ----------

def find_editable_version(app_id: str, token: str) -> dict:
    """Return the appStoreVersion record we're allowed to edit (prefer 1.0 in an editable state)."""
    q = urllib.parse.urlencode({
        "filter[versionString]": VERSION_STRING,
        "limit": "5",
    })
    status, d = api("GET", f"/v1/apps/{app_id}/appStoreVersions?{q}", token)
    require(status, d, "list versions")
    editable_states = {
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
        "METADATA_REJECTED", "WAITING_FOR_REVIEW", "INVALID_BINARY",
    }
    for v in d.get("data", []):
        state = v["attributes"].get("appStoreState")
        if state in editable_states:
            return v
    # Fallback: any matching version
    if d.get("data"):
        return d["data"][0]
    raise SystemExit(f"no appStoreVersion {VERSION_STRING} found for app {app_id}")


def find_localization(version_id: str, token: str) -> dict:
    status, d = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", token)
    require(status, d, "list localizations")
    for loc in d.get("data", []):
        if loc["attributes"].get("locale") == LOCALE:
            return loc
    raise SystemExit(f"no {LOCALE} localization on version {version_id}")


# ---------- PATCH metadata ----------

def patch_localization(loc_id: str, token: str, dry: bool):
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": loc_id,
            "attributes": COPY,
        }
    }
    if dry:
        print(f"  [dry] would PATCH localization {loc_id} with {list(COPY.keys())}")
        return
    status, d = api("PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}", token, body)
    require(status, d, "patch localization")
    print(f"  ✓ localization updated ({loc_id})")


def patch_version_copyright(version_id: str, token: str, dry: bool):
    body = {
        "data": {
            "type": "appStoreVersions",
            "id": version_id,
            "attributes": {"copyright": COPYRIGHT},
        }
    }
    if dry:
        print(f"  [dry] would PATCH version {version_id} copyright → {COPYRIGHT!r}")
        return
    status, d = api("PATCH", f"/v1/appStoreVersions/{version_id}", token, body)
    require(status, d, "patch version copyright")
    print(f"  ✓ copyright set ({COPYRIGHT!r})")


# ---------- screenshots ----------

def list_screenshot_sets(loc_id: str, token: str) -> list:
    status, d = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", token)
    require(status, d, "list screenshot sets")
    return d.get("data", [])


def list_screenshots_in_set(set_id: str, token: str) -> list:
    status, d = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots", token)
    require(status, d, "list screenshots in set")
    return d.get("data", [])


def delete_screenshot_set(set_id: str, token: str):
    status, d = api("DELETE", f"/v1/appScreenshotSets/{set_id}", token)
    if status >= 300 and status != 404:
        raise SystemExit(f"failed to delete set {set_id} (status {status}): {d}")


def create_screenshot_set(loc_id: str, display_type: str, token: str) -> str:
    body = {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                }
            },
        }
    }
    status, d = api("POST", "/v1/appScreenshotSets", token, body)
    require(status, d, f"create screenshot set {display_type}")
    return d["data"]["id"]


def upload_screenshot(set_id: str, file_path: Path, token: str) -> None:
    data = file_path.read_bytes()
    size = len(data)
    # Reserve upload slot
    body = {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileName": file_path.name, "fileSize": size},
            "relationships": {
                "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
            },
        }
    }
    status, d = api("POST", "/v1/appScreenshots", token, body)
    require(status, d, f"reserve upload for {file_path.name}")
    shot_id = d["data"]["id"]
    ops = d["data"]["attributes"]["uploadOperations"]
    # Stream bytes to each upload operation
    for op in ops:
        offset = op["offset"]
        length = op["length"]
        chunk = data[offset:offset + length]
        req_headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        req = urllib.request.Request(
            op["url"], data=chunk, method=op["method"], headers=req_headers,
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                r.read()
        except urllib.error.HTTPError as e:
            raise SystemExit(
                f"screenshot chunk upload failed ({file_path.name}, offset {offset}): "
                f"status {e.code}, body {e.read().decode(errors='replace')[:400]}"
            )
    # Commit: mark uploaded + send md5 checksum
    md5 = hashlib.md5(data).hexdigest()
    body = {
        "data": {
            "type": "appScreenshots",
            "id": shot_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": md5},
        }
    }
    status, d = api("PATCH", f"/v1/appScreenshots/{shot_id}", token, body)
    require(status, d, f"commit upload for {file_path.name}")


# ---------- app previews (videos) ----------

def list_preview_sets(loc_id: str, token: str) -> list:
    status, d = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appPreviewSets", token)
    require(status, d, "list preview sets")
    return d.get("data", [])


def delete_preview_set(set_id: str, token: str):
    status, d = api("DELETE", f"/v1/appPreviewSets/{set_id}", token)
    if status >= 300 and status != 404:
        raise SystemExit(f"failed to delete preview set {set_id} (status {status}): {d}")


def create_preview_set(loc_id: str, display_type: str, token: str) -> str:
    body = {
        "data": {
            "type": "appPreviewSets",
            "attributes": {"previewType": display_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                }
            },
        }
    }
    status, d = api("POST", "/v1/appPreviewSets", token, body)
    require(status, d, f"create preview set {display_type}")
    return d["data"]["id"]


def upload_preview(set_id: str, file_path: Path, token: str) -> str:
    data = file_path.read_bytes()
    size = len(data)
    mime = "video/quicktime" if file_path.suffix.lower() == ".mov" else "video/mp4"
    body = {
        "data": {
            "type": "appPreviews",
            "attributes": {
                "fileName": file_path.name,
                "fileSize": size,
                "mimeType": mime,
            },
            "relationships": {
                "appPreviewSet": {"data": {"type": "appPreviewSets", "id": set_id}}
            },
        }
    }
    status, d = api("POST", "/v1/appPreviews", token, body)
    require(status, d, f"reserve upload for {file_path.name}")
    preview_id = d["data"]["id"]
    ops = d["data"]["attributes"]["uploadOperations"]
    for op in ops:
        offset = op["offset"]
        length = op["length"]
        chunk = data[offset:offset + length]
        req_headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        req = urllib.request.Request(
            op["url"], data=chunk, method=op["method"], headers=req_headers,
        )
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                r.read()
        except urllib.error.HTTPError as e:
            raise SystemExit(
                f"preview chunk upload failed ({file_path.name}, offset {offset}): "
                f"status {e.code}, body {e.read().decode(errors='replace')[:400]}"
            )
    md5 = hashlib.md5(data).hexdigest()
    body = {
        "data": {
            "type": "appPreviews",
            "id": preview_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": md5},
        }
    }
    status, d = api("PATCH", f"/v1/appPreviews/{preview_id}", token, body)
    require(status, d, f"commit upload for {file_path.name}")
    return preview_id


def publish_previews(loc_id: str, token: str, dry: bool):
    existing = list_preview_sets(loc_id, token)
    by_type = {s["attributes"]["previewType"]: s["id"] for s in existing}

    for display_type, file_path in PREVIEWS:
        if not file_path.exists():
            raise SystemExit(f"missing preview file: {file_path}")

        if dry:
            print(f"  [dry] would replace {display_type} preview with {file_path.name}")
            continue

        if display_type in by_type:
            old_id = by_type[display_type]
            print(f"  removing prior {display_type} preview set {old_id}")
            delete_preview_set(old_id, token)

        set_id = create_preview_set(loc_id, display_type, token)
        print(f"  created {display_type} preview set {set_id}")
        preview_id = upload_preview(set_id, file_path, token)
        kb = file_path.stat().st_size // 1024
        print(f"    ↳ uploaded {file_path.name} ({kb} KB) as {preview_id}")


def publish_screenshots(loc_id: str, token: str, dry: bool):
    existing = list_screenshot_sets(loc_id, token)
    by_type = {s["attributes"]["screenshotDisplayType"]: s["id"] for s in existing}

    for display_type, folder, filenames in SCREENSHOTS:
        files = [folder / n for n in filenames]
        missing = [f for f in files if not f.exists()]
        if missing:
            raise SystemExit(f"missing screenshot files: {missing}")

        if dry:
            print(f"  [dry] would replace {display_type} with {[f.name for f in files]}")
            continue

        # Tear down existing set for this display type so re-runs stay idempotent.
        if display_type in by_type:
            old_id = by_type[display_type]
            print(f"  removing prior {display_type} set {old_id}")
            delete_screenshot_set(old_id, token)

        set_id = create_screenshot_set(loc_id, display_type, token)
        print(f"  created {display_type} set {set_id}")
        for f in files:
            upload_screenshot(set_id, f, token)
            print(f"    ↳ uploaded {f.name} ({f.stat().st_size // 1024} KB)")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--no-upload", action="store_true", help="skip screenshot upload, metadata only")
    p.add_argument("--no-metadata", action="store_true", help="skip metadata patches, screenshots only")
    p.add_argument("--no-previews", action="store_true", help="skip app preview video upload")
    p.add_argument("--previews-only", action="store_true", help="only upload app previews")
    p.add_argument("--dry-run", action="store_true", help="print intended actions without hitting ASC")
    args = p.parse_args()

    if not CONFIG.exists():
        raise SystemExit(f"{CONFIG} not found. Copy asc-config.env.example and fill in values.")
    env = load_env(CONFIG)
    for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "ASC_APP_ID"):
        if not env.get(k):
            raise SystemExit(f"{k} not set in {CONFIG}")
    key_path = os.path.expanduser(env["ASC_KEY_PATH"])
    if not os.path.exists(key_path):
        raise SystemExit(f"ASC_KEY_PATH not found: {key_path}")

    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], key_path)
    print(f"▸ finding editable {VERSION_STRING} version for app {env['ASC_APP_ID']}")
    version = find_editable_version(env["ASC_APP_ID"], token)
    version_id = version["id"]
    state = version["attributes"].get("appStoreState")
    print(f"  version {version_id} state={state}")

    loc = find_localization(version_id, token)
    loc_id = loc["id"]
    print(f"  {LOCALE} localization {loc_id}")

    do_metadata = not (args.no_metadata or args.previews_only)
    do_screenshots = not (args.no_upload or args.previews_only)
    do_previews = not args.no_previews

    if do_metadata:
        print("▸ patching metadata")
        patch_localization(loc_id, token, args.dry_run)
        patch_version_copyright(version_id, token, args.dry_run)

    if do_screenshots:
        print("▸ publishing screenshots")
        publish_screenshots(loc_id, token, args.dry_run)

    if do_previews:
        print("▸ publishing app previews")
        publish_previews(loc_id, token, args.dry_run)

    print("✓ done")


if __name__ == "__main__":
    main()
