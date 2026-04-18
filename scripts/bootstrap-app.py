#!/usr/bin/env python3
"""One-shot bootstrapper for this app's App Store Connect presence.

Given an ASC API key (in scripts/asc-config.env), this script:
  1. Registers the bundle ID (POST /v1/bundleIds) if it doesn't exist yet.
  2. Creates the App Store Connect app record (POST /v1/apps) if it doesn't exist yet.
  3. Prints the numeric app id and (if the file is writable) stamps it into
     scripts/asc-config.env as ASC_APP_ID.

After this runs successfully you can trigger scripts/ship-to-testflight.sh and
the hourly cron — no more clicking through appstoreconnect.apple.com.

The only manual prerequisite is the ASC API key itself (Users and Access →
Integrations → App Store Connect API → "+"), because API keys cannot create
themselves. If you already have a key from another app in the same team, reuse
it — paste its values into scripts/asc-config.env and this script will pick
them up.

Usage:
    scripts/bootstrap-app.py                                   # uses values from asc-config.env
    scripts/bootstrap-app.py --name "Baseball Stats Tracker"   # override the public app name
    scripts/bootstrap-app.py --dry-run                         # don't write, just report

Requires: pip3 install --user 'pyjwt[crypto]'
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

try:
    import jwt  # PyJWT
except ImportError:
    sys.stderr.write("error: PyJWT not installed. run: pip3 install --user 'pyjwt[crypto]'\n")
    sys.exit(1)

API_BASE = "https://api.appstoreconnect.apple.com"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(SCRIPT_DIR, "asc-config.env")

DEFAULT_NAME = "Baseball Stat Tracker"
DEFAULT_SKU = "BaseballStatTracker"
DEFAULT_LOCALE = "en-US"
DEFAULT_BUNDLE_ID = "com.divinedavis.BaseballStatTracker"


def die(msg: str) -> None:
    sys.stderr.write(f"error: {msg}\n")
    sys.exit(1)


def load_env(path: str) -> dict[str, str]:
    if not os.path.isfile(path):
        die(f"{path} not found. Copy scripts/asc-config.env.example and fill it in.")
    env: dict[str, str] = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            v = v.strip().strip('"').strip("'")
            # expand $HOME etc.
            v = os.path.expandvars(v).replace("$HOME", os.path.expanduser("~"))
            if v.startswith("~"):
                v = os.path.expanduser(v)
            env[k.strip()] = v
    return env


def make_token(key_id: str, issuer: str, key_path: str) -> str:
    with open(key_path) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def api(method: str, path: str, token: str, body=None) -> tuple[int, dict]:
    url = f"{API_BASE}{path}"
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        body_str = e.read().decode()[:1200]
        try:
            return e.code, json.loads(body_str)
        except json.JSONDecodeError:
            return e.code, {"error": body_str}


def find_bundle_id(token: str, identifier: str) -> dict | None:
    q = urllib.parse.urlencode({"filter[identifier]": identifier, "limit": "1"})
    status, d = api("GET", f"/v1/bundleIds?{q}", token)
    if status != 200:
        die(f"bundleIds lookup failed: {status} {d}")
    return (d.get("data") or [None])[0]


def create_bundle_id(token: str, identifier: str, name: str) -> dict:
    body = {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": identifier,
                "name": name,
                "platform": "IOS",
            },
        }
    }
    status, d = api("POST", "/v1/bundleIds", token, body)
    if status not in (200, 201):
        die(f"bundle id registration failed: {status} {json.dumps(d)[:800]}")
    return d["data"]


def find_app(token: str, bundle_identifier: str) -> dict | None:
    q = urllib.parse.urlencode({"filter[bundleId]": bundle_identifier, "limit": "1"})
    status, d = api("GET", f"/v1/apps?{q}", token)
    if status != 200:
        die(f"apps lookup failed: {status} {d}")
    return (d.get("data") or [None])[0]


def create_app(token: str, bundle_id_resource: str, name: str, sku: str, locale: str) -> dict:
    body = {
        "data": {
            "type": "apps",
            "attributes": {
                "name": name,
                "primaryLocale": locale,
                "sku": sku,
                "bundleId": bundle_id_resource,  # For POST /v1/apps this is the Apple bundle identifier, NOT the resource id — see note below.
            },
        }
    }
    # Apple's POST /v1/apps quirk: the "bundleId" attribute here is the
    # *reverse-DNS identifier* (com.example.App), not the resource id that
    # came back from /v1/bundleIds. This is documented but easy to miss.
    status, d = api("POST", "/v1/apps", token, body)
    if status == 403 and "CREATE" in json.dumps(d):
        # Apple-wide limitation: POST /v1/apps returns FORBIDDEN regardless of
        # API key role. Only app creation in the web UI works. Degrade into a
        # guided manual step; a subsequent script re-run will discover the app.
        sys.stderr.write(
            "\n⚠ Apple does not allow creating App Store Connect app records via the API.\n"
            "  (POST /v1/apps returns 403 'resource apps does not allow CREATE' for every role.)\n\n"
            "Do this once in the web UI, then re-run this script to finish the bootstrap:\n\n"
            "  1. https://appstoreconnect.apple.com/apps → + → New App\n"
            "  2. Platforms: iOS\n"
            f"  3. Name: {name!r} (must be globally unique — try a variant if taken)\n"
            "  4. Primary Language: English (U.S.)\n"
            f"  5. Bundle ID: {bundle_id_resource} (now available in the dropdown — we just registered it)\n"
            f"  6. SKU: {sku}\n"
            "  7. User Access: Full Access\n"
            "  8. Create.\n\n"
            "Then: scripts/bootstrap-app.py\n"
        )
        sys.exit(2)
    if status not in (200, 201):
        die(
            "app creation failed: "
            f"{status} {json.dumps(d)[:1200]}\n"
            "Common causes:\n"
            "  - The app Name is already taken on the App Store (must be globally unique).\n"
            "  - The bundle identifier isn't registered yet (re-run to register it first)."
        )
    return d["data"]


def stamp_app_id_into_env(path: str, app_id: str) -> bool:
    """Rewrite ASC_APP_ID in place. Returns True if the file changed."""
    if not os.access(path, os.W_OK):
        return False
    with open(path) as f:
        content = f.read()
    new_content, n = re.subn(
        r"^ASC_APP_ID=.*$",
        f"ASC_APP_ID={app_id}",
        content,
        count=1,
        flags=re.MULTILINE,
    )
    if n == 0:
        new_content = content.rstrip() + f"\nASC_APP_ID={app_id}\n"
    if new_content == content:
        return False
    with open(path, "w") as f:
        f.write(new_content)
    return True


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", default=DEFAULT_NAME, help=f"Public App Store name (default: {DEFAULT_NAME!r})")
    ap.add_argument("--sku", default=DEFAULT_SKU, help=f"Internal SKU (default: {DEFAULT_SKU!r})")
    ap.add_argument("--locale", default=DEFAULT_LOCALE, help=f"Primary locale (default: {DEFAULT_LOCALE!r})")
    ap.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID, help=f"Bundle identifier (default: {DEFAULT_BUNDLE_ID!r})")
    ap.add_argument("--dry-run", action="store_true", help="Don't create anything or modify files")
    args = ap.parse_args()

    env = load_env(CONFIG_PATH)
    for required in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
        if not env.get(required):
            die(f"{required} missing in {CONFIG_PATH}")
    if not os.path.isfile(env["ASC_KEY_PATH"]):
        die(f"ASC_KEY_PATH does not exist: {env['ASC_KEY_PATH']}")

    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])

    # 1. Bundle ID
    print(f"▸ checking bundle id {args.bundle_id}")
    existing_bundle = find_bundle_id(token, args.bundle_id)
    if existing_bundle:
        print(f"  ✓ already registered (resource id {existing_bundle['id']})")
    elif args.dry_run:
        print("  (dry-run) would register new bundle id")
    else:
        created = create_bundle_id(token, args.bundle_id, args.name)
        print(f"  ✓ registered (resource id {created['id']})")

    # 2. App record
    print(f"▸ checking app record for {args.bundle_id}")
    existing_app = find_app(token, args.bundle_id)
    if existing_app:
        app_id = existing_app["id"]
        app_name = existing_app["attributes"].get("name", "?")
        print(f"  ✓ app already exists: {app_name!r} (ASC_APP_ID={app_id})")
    elif args.dry_run:
        print(f"  (dry-run) would create app named {args.name!r} with SKU {args.sku!r}")
        return
    else:
        created_app = create_app(token, args.bundle_id, args.name, args.sku, args.locale)
        app_id = created_app["id"]
        print(f"  ✓ created {args.name!r} (ASC_APP_ID={app_id})")

    # 3. Stamp into env file
    if args.dry_run:
        return
    if stamp_app_id_into_env(CONFIG_PATH, app_id):
        print(f"▸ wrote ASC_APP_ID={app_id} into {CONFIG_PATH}")
    else:
        print(f"▸ ASC_APP_ID={app_id} (could not write to {CONFIG_PATH} — set it manually)")

    print("\n✓ bootstrap complete. next step:")
    print("    scripts/ship-to-testflight.sh \"Initial TestFlight build\"")


if __name__ == "__main__":
    main()
