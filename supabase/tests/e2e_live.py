#!/usr/bin/env python3
"""Live end-to-end checks against the real project (local only, needs the PAT).

Creates a throwaway confirmed user (e2e-<uuid>@test.invalid) via the admin
API, exercises the endpoints as that user / as anon, then deletes the user
and its storage objects. Makes NO Anthropic calls: every ai-analyze-swing
request here is refused before the Claude call.

  python3 supabase/tests/e2e_live.py

The service-role key is fetched at runtime from the Management API and is
never printed or written to disk.
"""
import json, os, subprocess, sys, time, uuid, urllib.error, urllib.request

REF = "ifcsanqnrbefgsydcfgf"
BASE = f"https://{REF}.supabase.co"
UA = {"User-Agent": "curl/8.7.1"}

def http(method, url, headers=None, body=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    h = dict(UA); h.update(headers or {})
    if body is not None: h.setdefault("Content-Type", "application/json")
    for attempt in range(3):
        req = urllib.request.Request(url, data=data, method=method, headers=h)
        try:
            r = urllib.request.urlopen(req, timeout=60); return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()
        except urllib.error.URLError:   # transient TLS resets
            if attempt == 2: raise
            time.sleep(1 + attempt)

pat = os.environ.get("SUPABASE_ACCESS_TOKEN") or subprocess.check_output(
    ["security", "find-generic-password", "-a", os.environ["USER"], "-s", "supabase-pat-clockin", "-w"]).decode().strip()
_, keys = http("GET", f"https://api.supabase.com/v1/projects/{REF}/api-keys?reveal=true",
               {"Authorization": f"Bearer {pat}"})
keys = json.loads(keys)
def key(name): return next(k["api_key"] for k in keys if k.get("name") == name)
SERVICE, ANON = key("service_role"), key("anon")
svc = {"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}"}

def sql(q):
    s, b = http("POST", f"https://api.supabase.com/v1/projects/{REF}/database/query",
                {"Authorization": f"Bearer {pat}"}, {"query": q})
    assert s in (200, 201), b
    return json.loads(b)

failures = []
def check(name, cond, detail=""):
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f"  -> {detail}"))
    if not cond: failures.append(name)

email, pw = f"e2e-{uuid.uuid4()}@test.invalid", uuid.uuid4().hex
s, b = http("POST", f"{BASE}/auth/v1/admin/users", svc,
            {"email": email, "password": pw, "email_confirm": True})
assert s == 200, b
uid = json.loads(b)["id"]

def objects():
    return sql(f"select name from storage.objects where bucket_id='swing-media' and name like '{uid}/%'")

try:
    s, b = http("POST", f"{BASE}/auth/v1/token?grant_type=password", {"apikey": ANON},
                {"email": email, "password": pw})
    assert s == 200, b
    jwt = json.loads(b)["access_token"]
    user = {"apikey": ANON, "Authorization": f"Bearer {jwt}"}
    anon = {"apikey": ANON, "Authorization": f"Bearer {ANON}"}

    def upload(size, name=None, h=None):
        name = name or f"{uuid.uuid4()}.jpg"
        return http("POST", f"{BASE}/storage/v1/object/swing-media/{uid}/{name}",
                    dict(h or user, **{"Content-Type": "image/jpeg"}), raw=b"\xff" * size), f"{uid}/{name}"

    TESTS = sys.argv[1:] or ["m3", "l1", "l3", "l4"]

    # ---- M3: 5 MB bucket limit + 20 objects per user ------------------------
    if "m3" in TESTS:
        (s, b), _ = upload(5 * 1024 * 1024 + 1)
        check("m3: >5MB upload refused", s in (400, 413), f"{s} {b[:200]}")
        (s, b), _ = upload(1024)
        check("m3: small upload accepted", s == 200, f"{s} {b[:200]}")
        for i in range(19):
            upload(10)
        check("m3: user holds 20 objects", len(objects()) == 20, len(objects()))
        (s, b), _ = upload(10)
        check("m3: 21st object refused", s in (400, 403), f"{s} {b[:200]}")
        names = [f"{o['name']}" for o in objects()]
        http("DELETE", f"{BASE}/storage/v1/object/swing-media", svc, {"prefixes": names})
        check("m3: cleanup", len(objects()) == 0)

    # ---- L1: analyze deletes the media whatever the outcome ----------------
    if "l1" in TESTS:
        # Exhaust today's swings so the request is refused BEFORE any Claude call.
        sql(f"insert into public.daily_usage (user_id, day, swings_used) values ('{uid}', current_date, 99) "
            f"on conflict (user_id, day) do update set swings_used = 99")
        (s, b), path = upload(1024)
        check("l1: upload ok", s == 200, f"{s} {b[:200]}")
        s, b = http("POST", f"{BASE}/functions/v1/ai-analyze-swing", user,
                    {"storage_path": path, "media_kind": "photo"})
        check("l1: analyze refused by quota (no Claude call)", s == 402, f"{s} {b[:200]}")
        check("l1: media deleted after refused analyze", len(objects()) == 0, objects())
        # Sweep endpoint rejects callers without the secret.
        s, _ = http("POST", f"{BASE}/functions/v1/swing-media-sweep", anon, {})
        check("l1: sweep refuses anon", s == 403, s)
        expired = sql("select count(*) as n from public.swing_media_expired(30, 1000)")[0]["n"]
        check("l1: nothing older than 30 days in swing-media", expired == 0, expired)
        jobs = sql("select jobname from cron.job where jobname = 'swing-media-sweep' and active")
        check("l1: daily sweep cron scheduled", len(jobs) == 1, jobs)

    # ---- L4: anon can't read user tables; signed-in app reads still work ---
    if "l4" in TESTS:
        for t in ["subscriptions", "usage_counters", "daily_usage", "swing_analyses", "chat_messages", "app_events"]:
            s, b = http("GET", f"{BASE}/rest/v1/{t}?select=*&limit=1", anon)
            check(f"l4: anon SELECT {t} refused", s in (401, 403), f"{s} {b[:120]}")
        s, b = http("GET", f"{BASE}/rest/v1/tier_limits?select=*", anon)
        check("l4: anon reads tier_limits", s == 200 and len(json.loads(b)) == 3, f"{s} {b[:120]}")
        s, b = http("GET", f"{BASE}/rest/v1/subscriptions?select=tier,expires_at", user)
        check("l4: signed-in user reads own subscriptions (BillingStore)", s == 200, f"{s} {b[:120]}")
        s, b = http("POST", f"{BASE}/rest/v1/app_events", dict(user, Prefer="return=minimal"),
                    {"user_id": uid, "event": "e2e_probe", "properties": {}})
        check("l4: signed-in user inserts app_events (EventLogger)", s == 201, f"{s} {b[:160]}")

    # ---- L3: auth config + no email-verification step ----------------------
    if "l3" in TESTS:
        _, cfg = http("GET", f"https://api.supabase.com/v1/projects/{REF}/config/auth",
                      {"Authorization": f"Bearer {pat}"})
        cfg = json.loads(cfg)
        check("l3: site_url is the public site, not localhost",
              cfg["site_url"].startswith("https://") and "localhost" not in cfg["site_url"], cfg["site_url"])
        check("l3: no extra redirect URLs allowed", not cfg.get("uri_allow_list"), cfg.get("uri_allow_list"))
        check("l3: email signup needs no confirmation (owner rule)", cfg["mailer_autoconfirm"] is True)
        e2, p2 = f"e2e-{uuid.uuid4()}@test.invalid", uuid.uuid4().hex
        s, b = http("POST", f"{BASE}/auth/v1/signup", {"apikey": ANON}, {"email": e2, "password": p2})
        body = json.loads(b) if b.startswith("{") else {}
        check("l3: email signup returns a session immediately", s == 200 and body.get("access_token"), f"{s} {b[:200]}")
        new_id = (body.get("user") or {}).get("id")
        if new_id:
            http("DELETE", f"{BASE}/auth/v1/admin/users/{new_id}", svc)

finally:
    names = [o["name"] for o in objects()]
    if names:
        http("DELETE", f"{BASE}/storage/v1/object/swing-media", svc, {"prefixes": names})
    s, b = http("DELETE", f"{BASE}/auth/v1/admin/users/{uid}", svc)
    check("teardown: test user deleted", s == 200, f"{s} {b[:200]}")

sys.exit(1 if failures else 0)
