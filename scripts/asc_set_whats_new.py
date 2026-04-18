#!/usr/bin/env python3
"""Poll App Store Connect for a build reaching VALID state, then set its
"What to Test" (release notes) via betaBuildLocalizations.

Usage:
    asc_set_whats_new.py \
        --app-id 6762485508 \
        --version 1.1 \
        --build 2 \
        --key-id DCW4DGNGQ4 \
        --issuer 69a6de85-... \
        --key-path ~/.appstoreconnect/private_keys/AuthKey_DCW4DGNGQ4.p8 \
        --whats-new "- New Clock tab\\n- Fix login persistence"
"""
import argparse
import json
import os
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


def api(method: str, path: str, token: str, body=None):
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
        return e.code, {"error": e.read().decode()[:800]}


def find_build(app_id: str, version: str, build: str, token: str,
               max_wait_seconds: int = 1800, poll_interval: int = 15) -> str:
    """Poll until a matching build appears and reaches VALID state, return its resource id."""
    deadline = time.time() + max_wait_seconds
    seen_state = None
    while time.time() < deadline:
        q = urllib.parse.urlencode({
            "filter[app]": app_id,
            "filter[preReleaseVersion.version]": version,
            "filter[version]": build,
            "limit": "5",
        })
        status, d = api("GET", f"/v1/builds?{q}", token)
        if status != 200:
            print(f"  API error {status}: {d}")
            time.sleep(poll_interval)
            continue
        builds = d.get("data", [])
        if not builds:
            if seen_state != "pending_ingestion":
                print(f"  waiting for build {version} ({build}) to appear in the API...")
                seen_state = "pending_ingestion"
            time.sleep(poll_interval)
            continue
        b = builds[0]
        state = b["attributes"].get("processingState")
        if state != seen_state:
            print(f"  build {version} ({build}) state: {state}")
            seen_state = state
        if state == "VALID":
            return b["id"]
        if state in {"FAILED", "INVALID", "EXPIRED"}:
            raise SystemExit(f"build reached terminal state {state} — aborting")
        time.sleep(poll_interval)
    raise SystemExit(f"timed out after {max_wait_seconds}s waiting for VALID state")


def set_whats_new(build_id: str, whats_new: str, token: str, locale: str = "en-US") -> None:
    # Unescape \n literal sequences passed from the shell.
    whats_new = whats_new.replace("\\n", "\n")

    status, d = api("GET", f"/v1/builds/{build_id}/betaBuildLocalizations", token)
    if status != 200:
        raise SystemExit(f"failed to list localizations: {d}")
    existing = next(
        (l for l in d.get("data", []) if l["attributes"].get("locale") == locale),
        None,
    )
    if existing:
        body = {
            "data": {
                "type": "betaBuildLocalizations",
                "id": existing["id"],
                "attributes": {"whatsNew": whats_new},
            }
        }
        status, d = api("PATCH", f"/v1/betaBuildLocalizations/{existing['id']}", token, body)
    else:
        body = {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": locale, "whatsNew": whats_new},
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build_id}}
                },
            }
        }
        status, d = api("POST", "/v1/betaBuildLocalizations", token, body)
    if status >= 300:
        raise SystemExit(f"failed to set whats_new (status {status}): {d}")
    print(f"  release notes set on build {build_id} ({locale})")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--app-id", required=True)
    p.add_argument("--version", required=True, help="marketing version, e.g. 1.1")
    p.add_argument("--build", required=True, help="build number, e.g. 2")
    p.add_argument("--key-id", required=True)
    p.add_argument("--issuer", required=True)
    p.add_argument("--key-path", required=True)
    p.add_argument("--whats-new", required=True)
    p.add_argument("--locale", default="en-US")
    p.add_argument("--max-wait", type=int, default=1800)
    args = p.parse_args()

    token = make_token(args.key_id, args.issuer, args.key_path)
    build_id = find_build(args.app_id, args.version, args.build, token, args.max_wait)
    set_whats_new(build_id, args.whats_new, token, args.locale)


if __name__ == "__main__":
    main()
