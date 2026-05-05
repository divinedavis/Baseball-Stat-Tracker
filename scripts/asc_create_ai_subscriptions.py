#!/usr/bin/env python3
"""Create the two Barrel AI auto-renewable subscriptions in App Store Connect.

Idempotent — safe to re-run. Looks up existing subscription group + products
by reference name / productId and only creates what's missing. Sets:
  - Subscription group "Barrel AI" with display name "Barrel AI"
  - Standard ($9.99/mo, level 2) — productId aistandard.monthly
  - Pro ($24.99/mo, level 1) — productId aipro.monthly

Apple's subscription "level" goes top-down: level 1 = highest tier, so
an upgrade from Standard (2) to Pro (1) takes effect immediately while a
downgrade defers to the next renewal — the right behavior here.

Review screenshots aren't uploaded; products will sit in "Missing Metadata"
until you add a screenshot in ASC web UI before submitting for review.
That's fine for sandbox testing today.

Usage:
    scripts/asc_create_ai_subscriptions.py            # create / sync
    scripts/asc_create_ai_subscriptions.py --dry-run  # show what would change

Credentials: scripts/asc-config.env (ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH / ASC_APP_ID)
"""
from __future__ import annotations

import argparse
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

GROUP_REF_NAME = "Barrel AI"
GROUP_DISPLAY_NAME = "Barrel AI"
LOCALE = "en-US"

PRODUCTS = [
    {
        "ref_name": "Barrel AI Standard Monthly",
        "product_id": "com.divinedavis.BaseballStatTracker.aistandard.monthly",
        "level": 2,
        "price_usd": "9.99",
        "display_name": "Barrel AI Standard",
        "description": "15 swing analyses + 30 AI Q&A per month.",
        "review_note": (
            "Standard tier of Barrel AI. Subscribers can upload up to 15 swing "
            "photos/videos per month and ask up to 30 questions about hitting, "
            "with daily caps to prevent abuse."
        ),
    },
    {
        "ref_name": "Barrel AI Pro Monthly",
        "product_id": "com.divinedavis.BaseballStatTracker.aipro.monthly",
        "level": 1,
        "price_usd": "24.99",
        "display_name": "Barrel AI Pro",
        "description": "50 swing analyses + unlimited AI Q&A monthly.",
        "review_note": (
            "Pro tier of Barrel AI. Subscribers can upload up to 50 swing "
            "photos/videos per month with no question limit. 15 swings per day."
        ),
    },
]


# ---------- env + auth ----------

def load_env(path: Path) -> dict:
    env: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip().strip('"').strip("'")
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
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")[:6000]
        try:
            return e.code, json.loads(body_text)
        except Exception:
            return e.code, {"raw": body_text}


def must(status: int, body, what: str):
    if status >= 300:
        raise SystemExit(f"ASC API error on {what} (status {status}): {body}")
    return body


# ---------- subscription group ----------

def find_or_create_group(app_id: str, token: str, dry: bool) -> str:
    status, d = api(
        "GET",
        f"/v1/apps/{app_id}/subscriptionGroups?limit=200",
        token,
    )
    must(status, d, "list subscription groups")
    for g in d.get("data", []):
        if g["attributes"].get("referenceName") == GROUP_REF_NAME:
            print(f"  ✓ subscription group exists ({g['id']})")
            return g["id"]

    if dry:
        print(f"  [dry] would create subscription group '{GROUP_REF_NAME}'")
        return "DRY_GROUP_ID"

    body = {
        "data": {
            "type": "subscriptionGroups",
            "attributes": {"referenceName": GROUP_REF_NAME},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    status, d = api("POST", "/v1/subscriptionGroups", token, body)
    must(status, d, "create subscription group")
    gid = d["data"]["id"]
    print(f"  + created subscription group ({gid})")
    ensure_group_localization(gid, token, dry)
    return gid


def ensure_group_localization(group_id: str, token: str, dry: bool):
    status, d = api(
        "GET",
        f"/v1/subscriptionGroups/{group_id}/subscriptionGroupLocalizations",
        token,
    )
    must(status, d, "list group localizations")
    for loc in d.get("data", []):
        if loc["attributes"].get("locale") == LOCALE:
            return
    if dry:
        print(f"  [dry] would add {LOCALE} localization to group {group_id}")
        return
    body = {
        "data": {
            "type": "subscriptionGroupLocalizations",
            "attributes": {
                "name": GROUP_DISPLAY_NAME,
                "locale": LOCALE,
                "customAppName": None,
            },
            "relationships": {
                "subscriptionGroup": {
                    "data": {"type": "subscriptionGroups", "id": group_id}
                }
            },
        }
    }
    status, d = api("POST", "/v1/subscriptionGroupLocalizations", token, body)
    must(status, d, "create group localization")
    print(f"  + added {LOCALE} localization to group")


# ---------- subscription products ----------

def find_subscription(group_id: str, token: str, product_id: str) -> dict | None:
    status, d = api(
        "GET",
        f"/v1/subscriptionGroups/{group_id}/subscriptions?limit=200",
        token,
    )
    must(status, d, "list subscriptions in group")
    for s in d.get("data", []):
        if s["attributes"].get("productId") == product_id:
            return s
    return None


def create_subscription(group_id: str, token: str, spec: dict, dry: bool) -> str:
    if dry:
        print(f"  [dry] would create subscription {spec['product_id']}")
        return "DRY_SUB_ID"
    body = {
        "data": {
            "type": "subscriptions",
            "attributes": {
                "name": spec["ref_name"],
                "productId": spec["product_id"],
                "familySharable": False,
                "subscriptionPeriod": "ONE_MONTH",
                "groupLevel": spec["level"],
                "reviewNote": spec["review_note"],
            },
            "relationships": {
                "group": {"data": {"type": "subscriptionGroups", "id": group_id}}
            },
        }
    }
    status, d = api("POST", "/v1/subscriptions", token, body)
    must(status, d, f"create subscription {spec['product_id']}")
    sid = d["data"]["id"]
    print(f"  + created subscription {spec['product_id']} ({sid})")
    return sid


def ensure_localization(sub_id: str, token: str, spec: dict, dry: bool):
    status, d = api(
        "GET",
        f"/v1/subscriptions/{sub_id}/subscriptionLocalizations",
        token,
    )
    must(status, d, f"list localizations for {sub_id}")
    for loc in d.get("data", []):
        if loc["attributes"].get("locale") == LOCALE:
            print(f"    ✓ {LOCALE} localization exists")
            return
    if dry:
        print(f"    [dry] would add {LOCALE} localization to {sub_id}")
        return
    body = {
        "data": {
            "type": "subscriptionLocalizations",
            "attributes": {
                "name": spec["display_name"],
                "description": spec["description"],
                "locale": LOCALE,
            },
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sub_id}}
            },
        }
    }
    status, d = api("POST", "/v1/subscriptionLocalizations", token, body)
    must(status, d, f"create localization for {sub_id}")
    print(f"    + added {LOCALE} localization")


# ---------- pricing ----------

def find_usd_price_point(sub_id: str, token: str, target_price: str) -> str | None:
    """Find the USA price point whose customerPrice matches target_price."""
    next_url = (
        f"/v1/subscriptions/{sub_id}/pricePoints"
        f"?filter[territory]=USA&limit=200"
    )
    while next_url:
        status, d = api("GET", next_url, token)
        must(status, d, "list price points")
        for pp in d.get("data", []):
            if pp["attributes"].get("customerPrice") == target_price:
                return pp["id"]
        nxt = (d.get("links") or {}).get("next")
        if not nxt:
            return None
        # The next link is a full URL; pass through.
        next_url = nxt
    return None


def ensure_price(sub_id: str, token: str, target_price: str, dry: bool):
    """Set USD base price via the subscriptionPriceSchedules API.

    ASC migrated subscription pricing to "schedules" in 2024: a single POST
    creates a schedule containing one or more subscriptionPrices, with a
    base territory that Apple uses to auto-derive other regions. The price
    objects are passed in `included` and referenced by client-chosen tags.
    """
    status, d = api(
        "GET",
        f"/v1/subscriptions/{sub_id}/prices?include=subscriptionPricePoint",
        token,
    )
    must(status, d, "list current prices")
    if d.get("data"):
        included = {(i["type"], i["id"]): i for i in d.get("included", [])}
        for entry in d["data"]:
            pp_rel = entry.get("relationships", {}).get("subscriptionPricePoint", {}).get("data")
            if not pp_rel:
                continue
            pp = included.get((pp_rel["type"], pp_rel["id"]))
            if pp and pp["attributes"].get("customerPrice") == target_price:
                print(f"    ✓ price already set to ${target_price}")
                return

    pp_id = find_usd_price_point(sub_id, token, target_price)
    if pp_id is None:
        raise SystemExit(f"no USA price point matching ${target_price}")

    if dry:
        print(f"    [dry] would set price to ${target_price} (pp={pp_id})")
        return

    tag = "${usd-base}"
    body = {
        "data": {
            "type": "subscriptionPriceSchedules",
            "relationships": {
                "subscription": {
                    "data": {"type": "subscriptions", "id": sub_id}
                },
                "baseTerritory": {
                    "data": {"type": "territories", "id": "USA"}
                },
                "manualPrices": {
                    "data": [{"type": "subscriptionPrices", "id": tag}]
                },
            },
        },
        "included": [
            {
                "type": "subscriptionPrices",
                "id": tag,
                "attributes": {"startDate": None},
                "relationships": {
                    "subscriptionPricePoint": {
                        "data": {"type": "subscriptionPricePoints", "id": pp_id}
                    },
                    "territory": {"data": {"type": "territories", "id": "USA"}},
                },
            }
        ],
    }
    status, d = api("POST", "/v1/subscriptionPriceSchedules", token, body)
    if status >= 300:
        print(
            f"    ! could not set price programmatically (status {status}). "
            f"Set ${target_price} in ASC web UI under this subscription."
        )
        return
    print(f"    + price set to ${target_price}")


# ---------- main ----------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not CONFIG.exists():
        raise SystemExit(f"missing {CONFIG}")
    env = load_env(CONFIG)
    for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "ASC_APP_ID"):
        if not env.get(k):
            raise SystemExit(f"{k} not set in {CONFIG}")

    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])
    app_id = env["ASC_APP_ID"]
    dry = args.dry_run

    print(f"▸ subscription group: {GROUP_REF_NAME}")
    group_id = find_or_create_group(app_id, token, dry)

    for spec in PRODUCTS:
        print(f"\n▸ {spec['display_name']} ({spec['product_id']})")
        existing = find_subscription(group_id, token, spec["product_id"])
        if existing:
            sub_id = existing["id"]
            print(f"  ✓ subscription exists ({sub_id})")
        else:
            sub_id = create_subscription(group_id, token, spec, dry)
        ensure_localization(sub_id, token, spec, dry)
        ensure_price(sub_id, token, spec["price_usd"], dry)

    print("\n✓ done")


if __name__ == "__main__":
    main()
