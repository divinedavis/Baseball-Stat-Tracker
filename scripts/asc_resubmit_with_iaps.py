#!/usr/bin/env python3
"""Resubmit Barrel v1.2 to App Review with the two AI subscriptions attached.

Addresses the 2.1(b) rejection where IAP products were not submitted alongside
the version. Run AFTER the new TestFlight build finishes processing.

Steps:
  1. Look up app version 1.2 + the two subscription product IDs.
  2. Find the in-progress reviewSubmission for the app (creates one if needed).
  3. Ensure the version is a reviewSubmissionItem (already is from the rejected run).
  4. Add reviewSubmissionItems for both subscriptions.
  5. (Optional) Update the version's attached build to the latest valid build.
  6. PATCH the reviewSubmission with submitted=true.

Idempotent: skips items that already exist; safe to re-run.

Usage:
    scripts/asc_resubmit_with_iaps.py            # do it
    scripts/asc_resubmit_with_iaps.py --dry-run  # show plan, no writes
    scripts/asc_resubmit_with_iaps.py --build N  # also attach build (CFBundleVersion N)
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

import jwt

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "scripts" / "asc-config.env"
API = "https://api.appstoreconnect.apple.com"

VERSION_STRING = "1.2"
SUB_PRODUCT_IDS = [
    "com.divinedavis.BaseballStatTracker.aistandard.monthly",
    "com.divinedavis.BaseballStatTracker.aipro.monthly",
]


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


def must(status, body, what):
    if status >= 300:
        raise SystemExit(f"ASC API error on {what} (status {status}): {json.dumps(body)[:1500]}")
    return body


# ---------- lookups ----------

def find_version(app_id, token):
    s, d = must(*api("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=20", token), "list app versions"), None
    for v in s.get("data", []):
        if v["attributes"].get("versionString") == VERSION_STRING:
            return v
    raise SystemExit(f"version {VERSION_STRING} not found")


def find_subscriptions(app_id, token):
    """Return [{product_id, sub_id, state}] for the two AI subs."""
    # Find groups
    s, d = api("GET", f"/v1/apps/{app_id}/subscriptionGroups?limit=50", token)
    must(s, d, "list subscription groups")
    out = []
    for g in d.get("data", []):
        gid = g["id"]
        s2, d2 = api("GET", f"/v1/subscriptionGroups/{gid}/subscriptions?limit=50", token)
        must(s2, d2, "list subscriptions")
        for sub in d2.get("data", []):
            pid = sub["attributes"].get("productId")
            if pid in SUB_PRODUCT_IDS:
                out.append({"product_id": pid, "sub_id": sub["id"], "state": sub["attributes"].get("state")})
    found = {x["product_id"] for x in out}
    missing = set(SUB_PRODUCT_IDS) - found
    if missing:
        raise SystemExit(f"could not find subscriptions: {missing}")
    return out


def cancel_submission(submission_id, token, dry):
    if dry:
        print(f"  [dry] would cancel submission {submission_id}")
        return
    body = {
        "data": {
            "type": "reviewSubmissions",
            "id": submission_id,
            "attributes": {"canceled": True},
        }
    }
    s, d = api("PATCH", f"/v1/reviewSubmissions/{submission_id}", token, body)
    if s >= 300:
        # Try alternate attribute name
        body["data"]["attributes"] = {"state": "CANCELING"}
        s, d = api("PATCH", f"/v1/reviewSubmissions/{submission_id}", token, body)
    must(s, d, f"cancel submission {submission_id}")
    print(f"  ✓ canceled submission {submission_id}")


def find_or_create_submission(app_id, token, dry):
    s, d = api("GET", f"/v1/reviewSubmissions?filter[app]={app_id}&limit=10", token)
    must(s, d, "list review submissions")

    # READY_FOR_REVIEW = open, can accept items, can be submitted
    open_submissions = [r for r in d.get("data", []) if r["attributes"].get("state") == "READY_FOR_REVIEW"]
    if open_submissions:
        rs = open_submissions[0]
        print(f"  ✓ using existing open submission {rs['id']}")
        return rs["id"]

    # UNRESOLVED_ISSUES, IN_REVIEW etc. can't accept new items — cancel any UNRESOLVED ones
    blocking = [r for r in d.get("data", []) if r["attributes"].get("state") == "UNRESOLVED_ISSUES"]
    for r in blocking:
        print(f"  ! found rejected submission {r['id']} — canceling so we can create a fresh one")
        cancel_submission(r["id"], token, dry)

    if dry:
        print("  [dry] would create new reviewSubmission")
        return "DRY_SUB"
    body = {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    s, d = api("POST", "/v1/reviewSubmissions", token, body)
    must(s, d, "create review submission")
    rid = d["data"]["id"]
    print(f"  + created submission {rid}")
    return rid


def list_items(submission_id, token):
    s, d = api("GET", f"/v1/reviewSubmissions/{submission_id}/items?limit=50", token)
    must(s, d, "list submission items")
    return d.get("data", [])


def add_version_item(submission_id, version_id, token, existing_items, dry):
    for it in existing_items:
        rel = it.get("relationships", {}).get("appStoreVersion", {}).get("data")
        if rel and rel.get("id") == version_id:
            print("  ✓ version item already attached")
            return
    if dry:
        print("  [dry] would add appStoreVersion item")
        return
    body = {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
            },
        }
    }
    s, d = api("POST", "/v1/reviewSubmissionItems", token, body)
    must(s, d, "add version item")
    print("  + added appStoreVersion item")


def add_subscription_item(submission_id, sub, token, existing_items, dry):
    for it in existing_items:
        rel = it.get("relationships", {}).get("subscription", {}).get("data")
        if rel and rel.get("id") == sub["sub_id"]:
            print(f"  ✓ subscription {sub['product_id']} already in submission")
            return
    if dry:
        print(f"  [dry] would add subscription {sub['product_id']}")
        return
    body = {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                "subscription": {"data": {"type": "subscriptions", "id": sub["sub_id"]}},
            },
        }
    }
    s, d = api("POST", "/v1/reviewSubmissionItems", token, body)
    must(s, d, f"add subscription item {sub['product_id']}")
    print(f"  + added subscription {sub['product_id']}")


def attach_build(version_id, token, build_id, dry):
    # PATCH the version's build relationship
    if dry:
        print(f"  [dry] would attach build {build_id} to version")
        return
    body = {"data": {"type": "builds", "id": build_id}}
    s, d = api(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}/relationships/build",
        token,
        body,
    )
    must(s, d, "attach build to version")
    print(f"  + attached build {build_id} to version")


def find_build_id(app_id, token, build_number):
    s, d = api(
        "GET",
        f"/v1/builds?filter[app]={app_id}&filter[preReleaseVersion.version]={VERSION_STRING}&limit=20",
        token,
    )
    must(s, d, "list builds")
    for b in d.get("data", []):
        if b["attributes"].get("version") == str(build_number):
            return b["id"], b["attributes"].get("processingState")
    return None, None


def submit_for_review(submission_id, token, dry):
    if dry:
        print("  [dry] would PATCH submitted=true")
        return
    body = {
        "data": {
            "type": "reviewSubmissions",
            "id": submission_id,
            "attributes": {"submitted": True},
        }
    }
    s, d = api("PATCH", f"/v1/reviewSubmissions/{submission_id}", token, body)
    must(s, d, "submit reviewSubmission")
    print(f"  ✓ submitted reviewSubmission {submission_id} for App Review")


# ---------- main ----------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--build", type=int, help="attach build (CFBundleVersion) to v1.2 before submitting")
    parser.add_argument("--no-submit", action="store_true", help="prepare submission but don't submit")
    args = parser.parse_args()

    env = load_env(CONFIG)
    token = make_token(env)
    app_id = env["ASC_APP_ID"]
    dry = args.dry_run

    print(f"▸ finding version {VERSION_STRING}")
    version = find_version(app_id, token)
    version_id = version["id"]
    print(f"  ✓ version {VERSION_STRING} id={version_id} state={version['attributes'].get('appVersionState')}")

    print("\n▸ finding subscriptions")
    subs = find_subscriptions(app_id, token)
    for sub in subs:
        print(f"  ✓ {sub['product_id']} id={sub['sub_id']} state={sub['state']}")

    if args.build is not None:
        print(f"\n▸ attaching build {args.build}")
        bid, state = find_build_id(app_id, token, args.build)
        if not bid:
            raise SystemExit(f"build {args.build} not found in App Store Connect")
        if state != "VALID":
            raise SystemExit(f"build {args.build} is in state {state} — wait for VALID")
        attach_build(version_id, token, bid, dry)

    print("\n▸ finding/creating reviewSubmission")
    submission_id = find_or_create_submission(app_id, token, dry)

    if not dry:
        items = list_items(submission_id, token)
    else:
        items = []

    print("\n▸ ensuring submission items")
    add_version_item(submission_id, version_id, token, items, dry)
    if not dry:
        items = list_items(submission_id, token)
    for sub in subs:
        add_subscription_item(submission_id, sub, token, items, dry)

    if args.no_submit:
        print("\n--no-submit set; stopping before submit")
        return

    print("\n▸ submitting for review")
    submit_for_review(submission_id, token, dry)

    print("\n✓ done")


if __name__ == "__main__":
    main()
