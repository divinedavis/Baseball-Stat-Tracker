#!/usr/bin/env python3
"""Close the last gaps between "Prepare for Submission" and "Add for Review".

Assumes asc_publish_metadata.py has already run (screenshots, previews,
description, keywords, copyright, URLs, review contact info). This script
patches:

  1. Primary + secondary category on the editable appInfo (SPORTS / UTILITIES)
  2. Age rating declaration — everything set to NONE for a 4+ rating
  3. App Review notes — local-auth explanation so reviewers don't try to
     sign in with pre-provisioned credentials that don't exist yet
  4. Pricing — Free, USA as base territory (propagates worldwide)
  5. App Privacy — "No Data Collected" + publish the privacy notice

Re-runnable: every step is idempotent (PATCHes existing resources or
checks before creating).
"""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_publish_metadata import (
    load_env, make_token, api, require, CONFIG, API,
)

PRIMARY_CATEGORY = "SPORTS"
SECONDARY_CATEGORY = "UTILITIES"

REVIEW_NOTES = (
    "No sign-in credentials needed. On first launch the app shows an auth "
    "screen with two options:\n\n"
    "  • \"Sign in with Apple\" — uses the reviewer's own Apple ID "
    "(standard Apple flow)\n"
    "  • \"Continue with email\" → \"Create account\" — creates a local-only "
    "account on-device. Any email + password (6+ chars) + display name "
    "works; there is no backend server validating credentials.\n\n"
    "All data (roster, at-bats, game logs) is stored locally on the device. "
    "There is no backend, no analytics, no tracking. The app does not "
    "collect any user data and works fully offline."
)


def patch_categories(info_id: str, token: str):
    body = {
        "data": {
            "type": "appInfos",
            "id": info_id,
            "relationships": {
                "primaryCategory": {"data": {"type": "appCategories", "id": PRIMARY_CATEGORY}},
                "secondaryCategory": {"data": {"type": "appCategories", "id": SECONDARY_CATEGORY}},
            },
        }
    }
    status, d = api("PATCH", f"/v1/appInfos/{info_id}", token, body)
    require(status, d, "patch categories")
    print(f"  ✓ primary={PRIMARY_CATEGORY} secondary={SECONDARY_CATEGORY}")


def patch_age_rating(decl_id: str, token: str):
    # Apple's declaration mixes booleans (does the app have this feature?)
    # with enums (how intense is this content?). Defaults below yield 4+.
    attrs = {
        # Boolean flags — false means "feature not present"
        "advertising": False,
        "gambling": False,
        "healthOrWellnessTopics": False,
        "lootBox": False,
        "messagingAndChat": False,
        "parentalControls": False,
        "unrestrictedWebAccess": False,
        "userGeneratedContent": False,
        "ageAssurance": False,
        # Enum frequency/intensity fields — NONE means "no such content"
        "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        "contests": "NONE",
        "gamblingSimulated": "NONE",
        "gunsOrOtherWeapons": "NONE",
        "medicalOrTreatmentInformation": "NONE",
        "profanityOrCrudeHumor": "NONE",
        "sexualContentGraphicAndNudity": "NONE",
        "sexualContentOrNudity": "NONE",
        "horrorOrFearThemes": "NONE",
        "matureOrSuggestiveThemes": "NONE",
        "violenceCartoonOrFantasy": "NONE",
        "violenceRealistic": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE",
        # Overrides — NONE means "use Apple's computed rating as-is"
        "ageRatingOverride": "NONE",
        "koreaAgeRatingOverride": "NONE",
    }
    body = {"data": {"type": "ageRatingDeclarations", "id": decl_id, "attributes": attrs}}
    status, d = api("PATCH", f"/v1/ageRatingDeclarations/{decl_id}", token, body)
    require(status, d, "patch age rating")
    print("  ✓ age rating declaration patched (4+)")


def patch_review_notes(detail_id: str, token: str):
    body = {
        "data": {
            "type": "appStoreReviewDetails",
            "id": detail_id,
            "attributes": {"notes": REVIEW_NOTES},
        }
    }
    status, d = api("PATCH", f"/v1/appStoreReviewDetails/{detail_id}", token, body)
    require(status, d, "patch review notes")
    print(f"  ✓ review notes set ({len(REVIEW_NOTES)} chars)")


def configure_pricing(app_id: str, token: str):
    # Check if a price schedule already exists for this app.
    status, d = api("GET", f"/v1/apps/{app_id}/appPriceSchedule", token)
    if d.get("data"):
        print(f"  pricing already configured (schedule {d['data']['id']}) — skipping create")
        return
    # Find the USD $0.00 (Free) price point for this app.
    # appPricePoints are app-scoped because they factor in commission/VAT.
    status, d = api("GET", f"/v1/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=200", token, raw_body=None)
    require(status, d, "list price points")
    free = None
    for pp in d.get("data", []):
        if pp["attributes"].get("customerPrice") == "0.00":
            free = pp["id"]
            break
    if not free:
        raise SystemExit("could not find USD 0.00 price point for this app (Apple may have changed the endpoint)")
    print(f"  found free price point: {free}")

    body = {
        "data": {
            "type": "appPriceSchedules",
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free-price}"}]},
            },
        },
        "included": [
            {
                "type": "appPrices",
                "id": "${free-price}",
                "attributes": {"startDate": None},
                "relationships": {
                    "appPricePoint": {"data": {"type": "appPricePoints", "id": free}}
                },
            }
        ],
    }
    status, d = api("POST", "/v1/appPriceSchedules", token, body)
    require(status, d, "create price schedule")
    print(f"  ✓ priced Free (schedule {d['data']['id']})")


def configure_privacy(app_id: str, token: str):
    # "No Data Collected" means: no appDataUsages declared, then publish.
    # Step 1: ensure zero data-usage entries. (This app doesn't collect data.)
    status, d = api("GET", f"/v1/apps/{app_id}/appDataUsages?limit=50", token)
    existing = d.get("data", [])
    if existing:
        print(f"  warning: {len(existing)} appDataUsages already declared — not removing")
        # Don't auto-delete these; could be legitimate user choices.
    # Step 2: publish the privacy state. Endpoint is appDataUsagesPublishState.
    # First GET to find the resource id.
    status, d = api("GET", f"/v1/apps/{app_id}/dataUsagePublishState", token)
    if status == 200 and d.get("data"):
        publish_id = d["data"]["id"]
        attrs = d["data"]["attributes"]
        if attrs.get("published"):
            print("  privacy already published — skipping")
            return
        body = {
            "data": {
                "type": "appDataUsagesPublishState",
                "id": publish_id,
                "attributes": {"published": True},
            }
        }
        s2, pd = api("PATCH", f"/v1/appDataUsagesPublishState/{publish_id}", token, body)
        if s2 >= 300:
            print(f"  warn: could not publish privacy state ({s2}): {pd}")
        else:
            print("  ✓ privacy published — No Data Collected")
    else:
        print(f"  couldn't find publish state resource (status {status}): {str(d)[:200]}")


def main():
    env = load_env(CONFIG)
    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])
    app_id = env["ASC_APP_ID"]

    # Resolve ids once
    status, d = api("GET", f"/v1/apps/{app_id}/appInfos", token)
    require(status, d, "list appInfos")
    editable = next(
        (i for i in d["data"] if i["attributes"].get("state") == "PREPARE_FOR_SUBMISSION"),
        None,
    ) or d["data"][0]
    info_id = editable["id"]
    print(f"▸ editable appInfo: {info_id}")

    # Age rating declaration id (1:1 with appInfo)
    status, d = api("GET", f"/v1/appInfos/{info_id}/ageRatingDeclaration", token)
    decl_id = d["data"]["id"]

    # Review detail id
    ver_id = "98ad3db1-3b9f-43ca-88c1-0f331cb2ed4c"
    status, d = api("GET", f"/v1/appStoreVersions/{ver_id}/appStoreReviewDetail", token)
    detail_id = d["data"]["id"]

    print("\n▸ categories")
    patch_categories(info_id, token)

    print("\n▸ age rating")
    patch_age_rating(decl_id, token)

    print("\n▸ review notes")
    patch_review_notes(detail_id, token)

    print("\n▸ pricing")
    configure_pricing(app_id, token)

    print("\n▸ app privacy")
    configure_privacy(app_id, token)

    print("\n✓ finalize complete")


if __name__ == "__main__":
    main()
