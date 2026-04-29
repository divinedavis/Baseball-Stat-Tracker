#!/usr/bin/env python3
"""Patch the last en-US gaps and submit App Store v1.1 for review.

Closes en-US subtitle + promotional text (es-MX is already complete),
re-runs the finalize checklist (categories, age rating, review notes,
pricing, privacy) against the editable v1.1, then submits the version
through the reviewSubmissions API.

Idempotent up to the submit step. Once submitted, Apple's review
queue takes over and you can't edit metadata until rejected/approved.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_publish_es_metadata import (  # noqa: E402
    CONFIG, api, find_editable_version, find_editable_app_info,
    load_env, make_token, require,
)
from asc_finalize_submission import (  # noqa: E402
    patch_categories, patch_age_rating, patch_review_notes,
    configure_pricing, configure_privacy,
)

VERSION = "1.1"
EN_LOCALE = "en-US"
EN_SUBTITLE = "Live Baseball Hitting Stats"
EN_PROMO = (
    "Find the sweet spot. Log every at-bat with one tap — "
    "AVG, OBP, SLG, OPS update live. No accounts, no cloud, "
    "no noise. Made for the dugout."
)


def patch_en_us(version_id: str, info_id: str, token: str) -> None:
    s, d = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", token)
    require(s, d, "list version localizations")
    en_v = next((l for l in d.get("data", []) if l["attributes"].get("locale") == EN_LOCALE), None)
    if en_v is None:
        raise SystemExit("no en-US version localization")
    body = {"data": {"type": "appStoreVersionLocalizations", "id": en_v["id"],
                     "attributes": {"promotionalText": EN_PROMO}}}
    s, d = api("PATCH", f"/v1/appStoreVersionLocalizations/{en_v['id']}", token, body)
    require(s, d, "patch en-US promotionalText")
    print(f"  ✓ en-US promotionalText set ({len(EN_PROMO)} chars)")

    s, d = api("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations", token)
    require(s, d, "list app info localizations")
    en_i = next((l for l in d.get("data", []) if l["attributes"].get("locale") == EN_LOCALE), None)
    if en_i is None:
        raise SystemExit("no en-US app info localization")
    body = {"data": {"type": "appInfoLocalizations", "id": en_i["id"],
                     "attributes": {"subtitle": EN_SUBTITLE}}}
    s, d = api("PATCH", f"/v1/appInfoLocalizations/{en_i['id']}", token, body)
    require(s, d, "patch en-US subtitle")
    print(f"  ✓ en-US subtitle set: {EN_SUBTITLE!r}")


def submit_for_review(app_id: str, version_id: str, token: str) -> None:
    s, d = api(
        "GET",
        f"/v1/reviewSubmissions?filter[app]={app_id}&filter[platform]=IOS&filter[state]=READY_FOR_REVIEW,COMPLETING",
        token,
    )
    submission = None
    for sub in d.get("data", []):
        if sub["attributes"].get("state") in ("READY_FOR_REVIEW", "COMPLETING"):
            submission = sub
            break

    if submission is None:
        body = {"data": {"type": "reviewSubmissions",
                         "attributes": {"platform": "IOS"},
                         "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}
        s, d = api("POST", "/v1/reviewSubmissions", token, body)
        require(s, d, "create review submission")
        submission = d["data"]
    sub_id = submission["id"]
    print(f"  review submission: {sub_id} state={submission['attributes'].get('state')}")

    s, d = api("GET", f"/v1/reviewSubmissions/{sub_id}/items", token)
    has_version = False
    for item in d.get("data", []):
        rel = (item.get("relationships", {}).get("appStoreVersion", {}) or {}).get("data")
        if rel and rel.get("id") == version_id:
            has_version = True
            break
    if not has_version:
        body = {"data": {"type": "reviewSubmissionItems",
                         "relationships": {
                             "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                             "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                         }}}
        s, d = api("POST", "/v1/reviewSubmissionItems", token, body)
        require(s, d, "add version to review submission")
        print(f"  ✓ added version {version_id} to submission")
    else:
        print(f"  · version {version_id} already in submission")

    body = {"data": {"type": "reviewSubmissions", "id": sub_id,
                     "attributes": {"submitted": True}}}
    s, d = api("PATCH", f"/v1/reviewSubmissions/{sub_id}", token, body)
    require(s, d, "submit review submission")
    print(f"  ✓ submitted for review")


def main() -> None:
    env = load_env(CONFIG)
    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])
    app_id = env["ASC_APP_ID"]

    print(f"▸ resolving v{VERSION}")
    version = find_editable_version(app_id, VERSION, token)
    if version is None:
        raise SystemExit(f"no editable v{VERSION}")
    version_id = version["id"]
    print(f"  version: {version_id} state={version['attributes'].get('appStoreState')}")

    info = find_editable_app_info(app_id, token)
    info_id = info["id"]
    print(f"  appInfo: {info_id}")

    print("\n▸ patching en-US (subtitle + promotional text)")
    patch_en_us(version_id, info_id, token)

    print("\n▸ categories")
    patch_categories(info_id, token)

    s, d = api("GET", f"/v1/appInfos/{info_id}/ageRatingDeclaration", token)
    require(s, d, "fetch age rating declaration")
    decl_id = d["data"]["id"]
    print("\n▸ age rating")
    patch_age_rating(decl_id, token)

    s, d = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail", token)
    require(s, d, "fetch review detail")
    detail_id = d["data"]["id"]
    print("\n▸ review notes")
    patch_review_notes(detail_id, token)

    print("\n▸ pricing")
    configure_pricing(app_id, token)

    print("\n▸ app privacy")
    configure_privacy(app_id, token)

    print("\n▸ submitting for review")
    submit_for_review(app_id, version_id, token)

    print("\n✓ submitted — Apple review typically takes 24–48h")


if __name__ == "__main__":
    main()
