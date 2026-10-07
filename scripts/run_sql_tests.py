#!/usr/bin/env python3
"""Run supabase/tests/sql/*.test.sql against the live project.

Each file is one DO block that raises 'ALL_TESTS_PASSED' as its last step,
so the transaction always rolls back and leaves no rows behind. Any other
error (a failed ASSERT, a SQL error) is a test failure.

Needs the Supabase PAT in the macOS keychain (service supabase-pat-clockin);
local only, not run in CI.
"""
import glob, json, os, subprocess, sys, urllib.error, urllib.request

REF = "ifcsanqnrbefgsydcfgf"
tok = os.environ.get("SUPABASE_ACCESS_TOKEN") or subprocess.check_output(
    ["security", "find-generic-password", "-a", os.environ["USER"], "-s", "supabase-pat-clockin", "-w"]
).decode().strip()
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "supabase", "tests", "sql")
files = sorted(glob.glob(os.path.join(root, "*.test.sql")))
if len(sys.argv) > 1:
    files = [f for f in files if any(a in f for a in sys.argv[1:])]
failed = 0
for f in files:
    req = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": open(f).read()}).encode(), method="POST",
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json",
                 "User-Agent": "curl/8.7.1"})
    try:
        urllib.request.urlopen(req).read()
        body = "completed without the ALL_TESTS_PASSED sentinel"
    except urllib.error.HTTPError as e:
        body = e.read().decode()
    name = os.path.basename(f)
    if "ALL_TESTS_PASSED" in body:
        print(f"ok   {name}")
    else:
        failed += 1
        print(f"FAIL {name}: {body[:500]}")
sys.exit(1 if failed else 0)
