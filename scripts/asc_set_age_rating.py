#!/usr/bin/env python3
"""Set the age-rating declaration on the editable App Store appInfo to land at
a 12+ rating, with userGeneratedContent=true to reflect that users upload
swing media and chat messages to our backend.

Apple computes the displayed age rating from the questionnaire answers plus
the optional `ageRatingOverrideV2` override. We:
  • set `userGeneratedContent` = true (accurate for swing uploads + AI chat)
  • set `ageRatingOverrideV2` = TWELVE_PLUS  (the floor we want for the gen-AI surface)

Idempotent: re-running PATCHes the same values.

Usage:
    scripts/asc_set_age_rating.py            # push
    scripts/asc_set_age_rating.py --dry-run  # show what would change
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
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

TARGET_ATTRS = {
    "userGeneratedContent": True,
    # Apple's V2 bands (2025): NONE / NINE_PLUS / THIRTEEN_PLUS / SIXTEEN_PLUS /
    # EIGHTEEN_PLUS / UNRATED. THIRTEEN_PLUS replaces the old "12+" band and
    # matches our PRIVACY.md minimum age (13).
    "ageRatingOverrideV2": "THIRTEEN_PLUS",
}


def load_env(path: Path) -> dict:
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        k, _, v = line.partition("=")
        v = v.strip().strip('"').strip("'")
        env[k.strip()] = os.path.expandvars(os.path.expanduser(v))
    return env


def make_token(key_id: str, issuer: str, key_path: str) -> str:
    with open(os.path.expanduser(key_path)) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )


def api(method: str, path: str, token: str, body=None, timeout=60):
    url = f"{API}{path}" if path.startswith("/") else path
    data = None if body is None else json.dumps(body).encode()
    headers = {"Authorization": f"Bearer {token}"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode(errors="replace")[:2000]}


def find_editable_appinfo(app_id: str, token: str) -> dict:
    status, d = api("GET", f"/v1/apps/{app_id}/appInfos?include=ageRatingDeclaration", token)
    if status >= 300:
        raise SystemExit(f"listing appInfos failed: {status} {d}")
    editable_states = {
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
        "METADATA_REJECTED", "WAITING_FOR_REVIEW", "INVALID_BINARY",
        "READY_FOR_REVIEW",
    }
    chosen = None
    for ai in d.get("data", []):
        if ai["attributes"].get("appStoreState") in editable_states:
            chosen = ai
            break
    if chosen is None:
        raise SystemExit("no editable appInfo (expected one in PREPARE_FOR_SUBMISSION).")
    rel = chosen["relationships"]["ageRatingDeclaration"]["data"]
    age_id = rel["id"]
    current = next((i["attributes"] for i in d.get("included", [])
                    if i["type"] == "ageRatingDeclarations" and i["id"] == age_id), {})
    return {"appInfoId": chosen["id"], "ageRatingId": age_id, "current": current}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    env = load_env(CONFIG)
    for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "ASC_APP_ID"):
        if k not in env:
            sys.exit(f"{k} missing from {CONFIG}")
    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])

    info = find_editable_appinfo(env["ASC_APP_ID"], token)
    print(f"editable appInfo: {info['appInfoId']}")
    print(f"ageRatingDeclaration: {info['ageRatingId']}")
    current = info["current"]
    delta = {k: v for k, v in TARGET_ATTRS.items() if current.get(k) != v}
    if not delta:
        print("already set as desired:")
        for k, v in TARGET_ATTRS.items():
            print(f"  {k}: {current.get(k)}")
        return

    print("changes:")
    for k, v in delta.items():
        print(f"  {k}: {current.get(k)!r} -> {v!r}")

    if args.dry_run:
        print("(dry-run; no PATCH issued)")
        return

    body = {
        "data": {
            "type": "ageRatingDeclarations",
            "id": info["ageRatingId"],
            "attributes": delta,
        }
    }
    status, d = api("PATCH", f"/v1/ageRatingDeclarations/{info['ageRatingId']}",
                    token, body=body)
    if status >= 300:
        sys.exit(f"PATCH failed: {status} {d}")
    new_attrs = d.get("data", {}).get("attributes", {})
    print("PATCH succeeded.")
    for k in TARGET_ATTRS:
        print(f"  {k}: {new_attrs.get(k)}")


if __name__ == "__main__":
    main()
