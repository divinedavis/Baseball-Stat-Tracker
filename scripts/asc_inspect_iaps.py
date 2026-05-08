#!/usr/bin/env python3
"""Inspect the Barrel AI subscriptions: state, review screenshot, submission readiness."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "scripts" / "asc-config.env"
API = "https://api.appstoreconnect.apple.com"

SUB_IDS = {
    "Standard (6766669338)": "6766669338",
    "Pro (6766669981)": "6766669981",
}


def load_env(path: Path) -> dict:
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip().strip('"').strip("'")
        env[k.strip()] = os.path.expandvars(os.path.expanduser(v))
    return env


def make_token(env):
    with open(os.path.expanduser(env["ASC_KEY_PATH"])) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": env["ASC_ISSUER_ID"], "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": env["ASC_KEY_ID"], "typ": "JWT"},
    )


def api(method, path, token, body=None):
    url = f"{API}{path}" if path.startswith("/") else path
    data = None if body is None else json.dumps(body).encode()
    headers = {"Authorization": f"Bearer {token}"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")[:8000]
        try:
            return e.code, json.loads(body_text)
        except Exception:
            return e.code, {"raw": body_text}


def main():
    env = load_env(CONFIG)
    token = make_token(env)

    # App version state
    print("=" * 70)
    print("APP VERSIONS")
    print("=" * 70)
    s, d = api("GET", f"/v1/apps/{env['ASC_APP_ID']}/appStoreVersions?limit=10", token)
    if s == 200:
        for v in d.get("data", []):
            attr = v["attributes"]
            print(f"  v{attr.get('versionString')} — state={attr.get('appStoreState')} — id={v['id']}")
    else:
        print(f"  error {s}: {d}")

    # Each subscription
    for name, sid in SUB_IDS.items():
        print()
        print("=" * 70)
        print(f"SUBSCRIPTION: {name}")
        print("=" * 70)

        s, d = api("GET", f"/v1/subscriptions/{sid}?include=appStoreReviewScreenshot,subscriptionLocalizations,prices", token)
        if s != 200:
            print(f"  error {s}: {d}")
            continue
        attrs = d["data"]["attributes"]
        rels = d["data"].get("relationships", {})
        print(f"  productId: {attrs.get('productId')}")
        print(f"  state: {attrs.get('state')}")
        print(f"  reviewNote: {attrs.get('reviewNote', '')[:80]}")
        print(f"  groupLevel: {attrs.get('groupLevel')}")

        # Review screenshot
        screenshot_rel = rels.get("appStoreReviewScreenshot", {}).get("data")
        if screenshot_rel:
            print(f"  ✓ review screenshot attached: {screenshot_rel}")
        else:
            print(f"  ✗ NO review screenshot")

        # Localizations summary
        for inc in d.get("included", []):
            if inc["type"] == "subscriptionLocalizations":
                a = inc["attributes"]
                print(f"  localization {a['locale']}: name='{a.get('name')}' desc='{a.get('description', '')[:60]}'")


if __name__ == "__main__":
    main()
