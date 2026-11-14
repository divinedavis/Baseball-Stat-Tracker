#!/usr/bin/env python3
"""Attach a processed TestFlight build to an App Store version and submit it
for App Review, all at once (never a phased release).

Steps (each idempotent):
  1. Find the App Store version (default: MARKETING_VERSION in project.yml).
  2. Set "What's New" per locale from scripts/release_notes/<version>.<locale>.txt
     (passed through as_paragraphs: plain paragraphs, never bullets).
  3. Set the App Review notes from scripts/review_notes.txt, and make sure
     each description ends with the Terms of Use (Apple EULA) and Privacy
     Policy links (auto-renewing subscriptions: guideline 3.1.2).
  4. releaseType = AFTER_APPROVAL and delete any phased release, so the
     approved version reaches everyone at once.
  5. Attach build N (must be VALID).
  6. Find/create the reviewSubmission, add the version, add any AI
     subscription that is not yet APPROVED as its own item.
  7. Open the App Review sandbox window, then PATCH submitted=true.

    /usr/bin/python3 scripts/asc_ship_version.py --build 78 [--version 1.3] [--dry-run] [--no-submit]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_apply_aso import as_paragraphs  # noqa: E402
from asc_resubmit_with_iaps import (  # noqa: E402
    CONFIG, add_subscription_item, add_version_item, api, attach_build,
    find_or_create_submission, find_subscriptions, list_items, load_env,
    make_token, must, submit_for_review,
)

ROOT = Path(__file__).resolve().parent.parent
NOTES_DIR = ROOT / "scripts" / "release_notes"
REVIEW_NOTES = ROOT / "scripts" / "review_notes.txt"


def marketing_version() -> str:
    m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', (ROOT / "project.yml").read_text())
    if not m:
        raise SystemExit("MARKETING_VERSION not found in project.yml")
    return m.group(1)


def find_version(app_id, version, token, dry=False):
    """The App Store version, created when App Store Connect does not have it yet."""
    d = must(*api("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=20", token), "list versions")
    for v in d.get("data", []):
        if v["attributes"].get("versionString") == version:
            return v
    if dry:
        raise SystemExit(f"[dry] App Store version {version} does not exist yet; a real run creates it")
    body = {"data": {"type": "appStoreVersions",
                     "attributes": {"platform": "IOS", "versionString": version},
                     "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}}
    created = must(*api("POST", "/v1/appStoreVersions", token, body), f"create version {version}")
    print(f"  ✓ created App Store version {version}")
    return created["data"]


def set_listing_urls(app_id, version_id, token, dry):
    """Support, marketing and privacy-policy addresses, every locale."""
    d = must(*api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", token),
             "list version localizations")
    for loc in d.get("data", []):
        a, locale = loc["attributes"], loc["attributes"]["locale"]
        if a.get("supportUrl") == SUPPORT and a.get("marketingUrl") == SUPPORT:
            print(f"  ✓ {locale} support + marketing URL already set")
            continue
        if dry:
            print(f"  [dry] {locale} support + marketing URL -> {SUPPORT}")
            continue
        body = {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                         "attributes": {"supportUrl": SUPPORT, "marketingUrl": SUPPORT}}}
        must(*api("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", token, body), f"patch URLs {locale}")
        print(f"  ✓ {locale} support + marketing URL -> {SUPPORT}")
    infos = must(*api("GET", f"/v1/apps/{app_id}/appInfos", token), "list app infos").get("data", [])
    # The editable app info is the one that is not live yet.
    editable = [i for i in infos if (i["attributes"].get("state") or i["attributes"].get("appStoreState"))
                not in ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE")] or infos
    for info in editable:
        locs = must(*api("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations", token), "list app info localizations")
        for loc in locs.get("data", []):
            locale = loc["attributes"]["locale"]
            if loc["attributes"].get("privacyPolicyUrl") == PRIVACY:
                print(f"  ✓ {locale} privacy policy URL already set")
                continue
            if dry:
                print(f"  [dry] {locale} privacy policy URL -> {PRIVACY}")
                continue
            body = {"data": {"type": "appInfoLocalizations", "id": loc["id"],
                             "attributes": {"privacyPolicyUrl": PRIVACY}}}
            must(*api("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", token, body), f"patch privacy URL {locale}")
            print(f"  ✓ {locale} privacy policy URL -> {PRIVACY}")


def set_whats_new(version_id, version, token, dry):
    d = must(*api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", token),
             "list version localizations")
    for loc in d.get("data", []):
        locale = loc["attributes"]["locale"]
        path = NOTES_DIR / f"{version}.{locale}.txt"
        if not path.exists():
            raise SystemExit(f"missing release notes for {locale}: {path}")
        text = as_paragraphs(path.read_text().strip())
        if dry:
            print(f"  [dry] {locale} whatsNew ({len(text)} chars)")
            continue
        body = {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                         "attributes": {"whatsNew": text}}}
        must(*api("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", token, body),
             f"patch whatsNew {locale}")
        print(f"  ✓ {locale} whatsNew set ({len(text)} chars)")


def set_review_notes(version_id, token, dry):
    notes = REVIEW_NOTES.read_text().strip()
    d = must(*api("GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail", token),
             "get review detail")
    detail = d.get("data")
    if not detail:
        raise SystemExit("version has no appStoreReviewDetail — create it in ASC first")
    if dry:
        print(f"  [dry] review notes ({len(notes)} chars)")
        return
    body = {"data": {"type": "appStoreReviewDetails", "id": detail["id"],
                     "attributes": {"notes": notes}}}
    must(*api("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}", token, body), "patch review notes")
    print(f"  ✓ review notes set ({len(notes)} chars)")


EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
PRIVACY = "https://divinedavis.com/barrel/privacy/"
SUPPORT = "https://divinedavis.com/barrel/support/"
# Where the policy lived until 1.3.1; replaced wherever a description still has it.
OLD_PRIVACY = "https://github.com/divinedavis/Baseball-Stat-Tracker/blob/main/PRIVACY.md"
LEGAL_FOOTER = {
    "en-US": f"Terms of Use (EULA): {EULA}\nPrivacy Policy: {PRIVACY}",
    "es-MX": f"Términos de uso (EULA): {EULA}\nPolítica de privacidad: {PRIVACY}",
}


def ensure_legal_links(version_id, token, dry):
    d = must(*api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", token),
             "list version localizations")
    for loc in d.get("data", []):
        locale = loc["attributes"]["locale"]
        current = (loc["attributes"].get("description") or "").rstrip()
        desc = current.replace(OLD_PRIVACY, PRIVACY)
        if "stdeula" in desc and PRIVACY in desc and desc == current:
            print(f"  ✓ {locale} description already links Terms + Privacy")
            continue
        footer = LEGAL_FOOTER.get(locale, LEGAL_FOOTER["en-US"])
        if "stdeula" in desc and PRIVACY in desc:
            new = desc                       # only the old policy address needed replacing
        else:
            new = f"{desc}\n\n{footer}" if desc else footer
        if len(new) > 4000:
            raise SystemExit(f"{locale} description would exceed 4000 chars")
        if dry:
            print(f"  [dry] {locale} description += legal links")
            continue
        body = {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                         "attributes": {"description": new}}}
        must(*api("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", token, body),
             f"patch description {locale}")
        print(f"  ✓ {locale} description now ends with Terms of Use + Privacy Policy links")


def release_all_at_once(version_id, token, dry):
    if dry:
        print("  [dry] releaseType=AFTER_APPROVAL, delete any phased release")
        return
    body = {"data": {"type": "appStoreVersions", "id": version_id,
                     "attributes": {"releaseType": "AFTER_APPROVAL"}}}
    must(*api("PATCH", f"/v1/appStoreVersions/{version_id}", token, body), "set releaseType")
    d = must(*api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionPhasedRelease", token),
             "get phased release")
    phased = d.get("data")
    if phased:
        must(*api("DELETE", f"/v1/appStoreVersionPhasedReleases/{phased['id']}", token),
             "delete phased release")
        print("  ✓ phased release removed")
    print("  ✓ releaseType=AFTER_APPROVAL, no phased release (everyone at once)")


def find_build(app_id, version, build, token):
    d = must(*api("GET", f"/v1/builds?filter[app]={app_id}&filter[preReleaseVersion.version]={version}"
                         f"&filter[version]={build}&limit=5", token), "list builds")
    for b in d.get("data", []):
        if b["attributes"].get("version") == str(build):
            return b["id"], b["attributes"].get("processingState")
    return None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default=None)
    ap.add_argument("--build", type=int, required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-submit", action="store_true")
    args = ap.parse_args()

    version = args.version or marketing_version()
    env = load_env(CONFIG)
    token = make_token(env)
    app_id = env["ASC_APP_ID"]
    dry = args.dry_run

    v = find_version(app_id, version, token, dry)
    vid = v["id"]
    print(f"▸ version {version} id={vid} state={v['attributes'].get('appStoreState')}")

    print("\n▸ release notes")
    set_whats_new(vid, version, token, dry)
    print("\n▸ review notes")
    set_review_notes(vid, token, dry)
    print("\n▸ legal links in description")
    ensure_legal_links(vid, token, dry)
    print("\n▸ support, marketing and privacy URLs")
    set_listing_urls(app_id, vid, token, dry)
    print("\n▸ release type")
    release_all_at_once(vid, token, dry)

    print(f"\n▸ build {args.build}")
    bid, state = find_build(app_id, version, args.build, token)
    if not bid:
        raise SystemExit(f"build {args.build} of {version} not found")
    if state != "VALID":
        raise SystemExit(f"build {args.build} is {state} — wait for VALID")
    attach_build(vid, token, bid, dry)

    print("\n▸ review submission")
    sid = find_or_create_submission(app_id, token, dry)
    items = [] if dry else list_items(sid, token)
    add_version_item(sid, vid, token, items, dry)
    for sub in find_subscriptions(app_id, token):
        if sub["state"] == "APPROVED":
            print(f"  ✓ {sub['product_id']} already APPROVED — not resubmitted")
            continue
        items = [] if dry else list_items(sid, token)
        add_subscription_item(sid, sub, token, items, dry)

    if args.no_submit:
        print("\n--no-submit set; stopping before submit")
        return
    print("\n▸ submit")
    submit_for_review(sid, token, dry)
    print("\n✓ done")


if __name__ == "__main__":
    main()
