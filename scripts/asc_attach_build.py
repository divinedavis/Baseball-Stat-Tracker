#!/usr/bin/env python3
"""Attach a processed TestFlight build to the app's App Store "Prepare for
Submission" version, so App Store Connect can derive the Apps-grid /
marketing icon from the build automatically.

Reads credentials from scripts/asc-config.env (same file the ship script
uses) unless overridden by CLI flags.

Usage (defaults pick the latest VALID build):
    scripts/asc_attach_build.py
    scripts/asc_attach_build.py --build 24 --version 1.0
"""
import argparse
import json
import os
import pathlib
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


def load_env(path: pathlib.Path) -> dict:
    env = {}
    if not path.exists():
        return env
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        v = v.strip().strip('"').strip("'")
        env[k.strip()] = os.path.expandvars(v)
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
        raw = e.read().decode(errors="replace")
        sys.stderr.write(f"HTTP {e.code} {method} {path}\n{raw}\n")
        raise


def find_prepare_version(token, app_id, marketing_version):
    """Find the iOS appStoreVersion with matching versionString that's still editable."""
    qs = urllib.parse.urlencode({
        "filter[platform]": "IOS",
        "filter[versionString]": marketing_version,
        "limit": 10,
    })
    _, body = api("GET", f"/v1/apps/{app_id}/appStoreVersions?{qs}", token)
    editable = {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "WAITING_FOR_REVIEW",
        "INVALID_BINARY",
    }
    for v in body.get("data", []):
        state = v.get("attributes", {}).get("appStoreState")
        if state in editable:
            return v["id"], state
    return None, None


def find_build(token, app_id, marketing_version, build_number=None):
    """Return build id for the given pre-release version + build number.
    If build_number is None, return the newest VALID build."""
    params = {
        "filter[app]": app_id,
        "filter[preReleaseVersion.version]": marketing_version,
        "filter[processingState]": "VALID",
        "sort": "-version",
        "limit": 20,
    }
    if build_number is not None:
        params["filter[version]"] = str(build_number)
    qs = urllib.parse.urlencode(params)
    _, body = api("GET", f"/v1/builds?{qs}", token)
    builds = body.get("data", [])
    if not builds:
        return None, None
    b = builds[0]
    return b["id"], b.get("attributes", {}).get("version")


def attach(token, version_id, build_id):
    return api(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}/relationships/build",
        token,
        body={"data": {"type": "builds", "id": build_id}},
    )


def main():
    here = pathlib.Path(__file__).resolve().parent
    env = load_env(here / "asc-config.env")

    ap = argparse.ArgumentParser()
    ap.add_argument("--app-id", default=env.get("ASC_APP_ID"))
    ap.add_argument("--key-id", default=env.get("ASC_KEY_ID"))
    ap.add_argument("--issuer", default=env.get("ASC_ISSUER_ID"))
    ap.add_argument("--key-path", default=env.get("ASC_KEY_PATH"))
    ap.add_argument("--version", default="1.0",
                    help="marketing version string (e.g. 1.0)")
    ap.add_argument("--build", default=None,
                    help="build number to attach (default: newest VALID)")
    args = ap.parse_args()

    missing = [k for k in ("app_id", "key_id", "issuer", "key_path") if not getattr(args, k)]
    if missing:
        sys.stderr.write(f"error: missing credentials: {missing}. Populate scripts/asc-config.env or pass flags.\n")
        sys.exit(2)

    token = make_token(args.key_id, args.issuer, args.key_path)

    build_id, build_num = find_build(token, args.app_id, args.version, args.build)
    if not build_id:
        sys.stderr.write(
            f"error: no VALID build found for version {args.version}"
            + (f" build {args.build}" if args.build else "")
            + "\n"
        )
        sys.exit(1)
    print(f"▸ using build {args.version} ({build_num}) — id {build_id}")

    version_id, state = find_prepare_version(token, args.app_id, args.version)
    if not version_id:
        sys.stderr.write(
            f"error: no editable App Store version found for {args.version}. "
            "Create one in ASC first.\n"
        )
        sys.exit(1)
    print(f"▸ target appStoreVersion {version_id} (state: {state})")

    status, _ = attach(token, version_id, build_id)
    if status in (200, 204):
        print(f"✓ attached build {args.version} ({build_num}) to version {version_id}")
    else:
        sys.stderr.write(f"error: unexpected status {status}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
