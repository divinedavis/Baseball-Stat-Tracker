#!/usr/bin/env python3
"""Inspect the live App Store Connect metadata for every editable version
and locale on the Barrel app. Prints subtitle, promotional text, keywords,
and description (truncated) so we can audit ASO without hitting the web UI.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import jwt
except ImportError:
    sys.stderr.write("error: PyJWT not installed. run: pip3 install --user 'pyjwt[crypto]'\n")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "scripts" / "asc-config.env"
API = "https://api.appstoreconnect.apple.com"


def load_env(path: Path) -> dict:
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip().strip('"').strip("'")
        v = os.path.expandvars(os.path.expanduser(v))
        env[k.strip()] = v
    return env


def make_token(key_id, issuer, key_path):
    with open(os.path.expanduser(key_path)) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )


def get(path, token):
    url = f"{API}{path}" if path.startswith("/") else path
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def main():
    env = load_env(CONFIG)
    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])
    app_id = env["ASC_APP_ID"]

    print(f"▸ App ID {app_id}")

    # Pull app info → primary subtitle lives on AppInfoLocalizations.
    info = get(f"/v1/apps/{app_id}/appInfos?include=appInfoLocalizations", token)
    print(f"\n=== App Info localizations (subtitle, promotional name) ===")
    for inc in info.get("included", []):
        if inc["type"] != "appInfoLocalizations":
            continue
        a = inc["attributes"]
        print(f"\nlocale: {a.get('locale')}")
        print(f"  name:     {a.get('name')}")
        print(f"  subtitle: {a.get('subtitle')}")
        print(f"  privacy:  {a.get('privacyPolicyUrl') or '—'}")

    # Versions + their localizations (keywords, description, promo text).
    versions = get(f"/v1/apps/{app_id}/appStoreVersions?limit=10", token)
    print(f"\n=== App Store Versions ===")
    for v in versions.get("data", []):
        a = v["attributes"]
        vstr = a.get("versionString")
        state = a.get("appStoreState")
        print(f"\n--- {vstr}  [{state}]  id={v['id']} ---")
        locs = get(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations", token)
        for loc in locs.get("data", []):
            la = loc["attributes"]
            print(f"\n  locale: {la.get('locale')}")
            print(f"    promo:    {la.get('promotionalText') or '—'}")
            kw = la.get('keywords') or ''
            print(f"    keywords ({len(kw)}/100): {kw}")
            print(f"    whats new:    {(la.get('whatsNew') or '—')[:200]}")
            desc = la.get('description') or ''
            print(f"    description ({len(desc)} chars):")
            for line in desc.splitlines()[:8]:
                print(f"      {line}")
            if len(desc.splitlines()) > 8:
                print("      ...")


if __name__ == "__main__":
    main()
