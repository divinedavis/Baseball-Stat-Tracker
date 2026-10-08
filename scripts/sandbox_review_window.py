#!/usr/bin/env python3
"""Open / inspect / close the App Review sandbox-purchase window.

The storekit webhook gate (migration 20261007120000_sandbox_tier_gate) makes
Sandbox purchases resolve to the free tier unless the buyer is on
sandbox_tier_allowlist OR billing_settings.sandbox_grants_open_until is in
the future. App Review buys with its own sandbox Apple ID, so the window must
be open while a build is in review or the reviewer's purchase unlocks nothing
(-> 2.1(b) rejection).

The submit scripts (asc_submit_for_review.py, asc_resubmit_with_iaps.py) call
open_window() right before they PATCH submitted=true, so nobody has to
remember. Opening never shortens an already-later window.

    scripts/sandbox_review_window.py status
    scripts/sandbox_review_window.py open [--days 14]
    scripts/sandbox_review_window.py extend-if-in-review [--days 14]
        # re-open for N days only while a version is WAITING_FOR_REVIEW /
        # IN_REVIEW (safe to run daily; does nothing otherwise)
    scripts/sandbox_review_window.py close
        # sandbox_grants_open_until = null (after approval, optional — the
        # window also just expires)

Uses the Supabase Management API SQL endpoint (database/query) only. Needs
the PAT in SUPABASE_ACCESS_TOKEN or the macOS keychain (service
supabase-pat-clockin), same as run_sql_tests.py. The token is never printed.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

REF = "ifcsanqnrbefgsydcfgf"
QUERY_URL = f"https://api.supabase.com/v1/projects/{REF}/database/query"
DEFAULT_DAYS = 14
MAX_DAYS = 30
IN_REVIEW_STATES = {"WAITING_FOR_REVIEW", "IN_REVIEW"}


def open_sql(days: int) -> str:
    if not isinstance(days, int) or isinstance(days, bool) or not 1 <= days <= MAX_DAYS:
        raise ValueError(f"days must be an int in 1..{MAX_DAYS}, got {days!r}")
    # greatest(): re-running never pulls an already-later window in.
    return (
        "update public.billing_settings set sandbox_grants_open_until = "
        f"greatest(coalesce(sandbox_grants_open_until, now()), now() + interval '{days} days') "
        "where id returning sandbox_grants_open_until;"
    )


STATUS_SQL = (
    "select sandbox_grants_open_until, sandbox_grants_open_until > now() as open "
    "from public.billing_settings where id;"
)
CLOSE_SQL = (
    "update public.billing_settings set sandbox_grants_open_until = null "
    "where id returning sandbox_grants_open_until;"
)


def _token() -> str:
    tok = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if tok:
        return tok
    return subprocess.check_output(
        ["security", "find-generic-password", "-a", os.environ["USER"],
         "-s", "supabase-pat-clockin", "-w"]
    ).decode().strip()


def run_sql(sql: str) -> list:
    req = urllib.request.Request(
        QUERY_URL, data=json.dumps({"query": sql}).encode(), method="POST",
        headers={"Authorization": f"Bearer {_token()}", "Content-Type": "application/json",
                 "User-Agent": "curl/8.7.1"})  # Cloudflare 1010s urllib's default UA
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"[]")
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Supabase SQL failed ({e.code}): {e.read().decode()[:300]}") from None


def _one(rows: list, what: str) -> dict:
    if not rows:
        raise RuntimeError(f"{what}: billing_settings row missing")
    return rows[0]


def open_window(days: int = DEFAULT_DAYS) -> str:
    until = _one(run_sql(open_sql(days)), "open")["sandbox_grants_open_until"]
    print(f"  ✓ sandbox purchases grant paid tiers until {until} (App Review window)")
    return until


def status() -> dict:
    row = _one(run_sql(STATUS_SQL), "status")
    state = "OPEN" if row.get("open") else "closed"
    print(f"  sandbox window {state}: sandbox_grants_open_until = {row['sandbox_grants_open_until']}")
    return row


def close_window() -> None:
    _one(run_sql(CLOSE_SQL), "close")
    print("  ✓ sandbox window closed (sandbox purchases -> free unless allowlisted)")


def versions_in_review() -> list[str]:
    """Version strings of this app currently waiting for / in App Review."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from asc_resubmit_with_iaps import CONFIG, api, load_env, make_token, must
    env = load_env(CONFIG)
    tok = make_token(env)
    d = must(*api("GET", f"/v1/apps/{env['ASC_APP_ID']}/appStoreVersions?limit=10", tok),
             "list app versions")
    return [v["attributes"]["versionString"] for v in d.get("data", [])
            if v["attributes"].get("appStoreState") in IN_REVIEW_STATES]


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("command", choices=["status", "open", "extend-if-in-review", "close"])
    p.add_argument("--days", type=int, default=DEFAULT_DAYS)
    a = p.parse_args(argv)
    if a.command == "status":
        status()
    elif a.command == "open":
        open_window(a.days)
    elif a.command == "close":
        close_window()
    else:
        live = versions_in_review()
        if live:
            print(f"  in review: {', '.join(live)}")
            open_window(a.days)
        else:
            print("  no version in review; window left as-is")
            status()
    return 0


if __name__ == "__main__":
    sys.exit(main())
