# Baseball Stat Tracker — Workflow Instructions

This file is the source of truth for how we work on this app. Claude reads it at the start of each session.

## ⚑ Rule #0: NEVER COMMIT SECRETS

**Nothing sensitive goes in this repo. Ever.** Not in code, not in comments, not in commit messages, not in committed log files.

### What "sensitive" means here

- App Store Connect API keys (`AuthKey_*.p8`) — these let anyone ship builds as us.
- `scripts/asc-config.env` (the real one, not `.example`) — contains `ASC_KEY_ID`, `ASC_ISSUER_ID`, numeric `ASC_APP_ID`.
- Apple signing certs / private keys / provisioning profiles (`.p12`, `.pem`, `.cer`, `.mobileprovision`).
- Any future backend tokens, database URLs with passwords, Supabase service keys, Firebase configs with API secrets, push-notification certs.
- Real user passwords or PII if we ever get test data (scrub before committing).

### Guardrails already in place

- `.gitignore` blocks `*.env` (except `*.env.example`), `*.p8`, `*.p12`, `*.pem`, `*.key`, `*.cer`, `*.mobileprovision`, `AuthKey_*`, `secrets.*`, `Secrets.swift`, `GoogleService-Info.plist`, and the cron log files.
- The real `scripts/asc-config.env` is ignored; only `asc-config.env.example` (all placeholders) is tracked.
- API keys live at `~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8` (`chmod 600`), outside the repo.

### Before every commit

```bash
git status
git diff --cached
```

If you accidentally stage something sensitive, **don't just `git reset`** — the file may still be in the object database. Unstage with `git rm --cached <file>`. If it was already pushed, **rotate the credential immediately** (revoke the ASC key in App Store Connect and issue a new one), then scrub history with `git filter-repo` or BFG and force-push. Rotating is always faster and safer than trying to hide a leaked secret.

---

## ⚑ Rule #1: PUSH TO GITHUB AND SHIP TO TESTFLIGHT AFTER EVERY CHANGE

**Non-negotiable.** After *every* code, asset, script, or doc change:

```bash
git add -A
git commit -m "<concise imperative subject>"
git push origin main
scripts/ship-to-testflight.sh --auto-notes     # run in background; takes 10–25 min
```

The hourly LaunchAgent was removed on 2026-04-18 — we ship per-change now, not hourly. Iteration is fast enough that batching lags the code; per-change ships keep TestFlight in lockstep with `main`.

If the push fails (repo doesn't exist, no auth, network), **stop and surface it immediately** — don't keep editing locally. If the ship fails, check `scripts/.cron.err.log` or the in-band log path the script prints.

**Ship serialization:** don't start a second ship while a prior one is still uploading or processing — the Apple upload step doesn't parallelize well. Wait for the prior task's completion notification before kicking off the next one.

One meaningful commit per logical change. Don't batch unrelated edits.

---

## ⚑ Rule #1b: UI CHANGES → RECAPTURE + RE-UPLOAD SCREENSHOTS

**If the change is visible in the app, the App Store listing's screenshots
must be updated in the same turn.** Stale screenshots mean the store page
shows a different app than what TestFlight / production ships.

Applies to any diff that could alter a marketing-relevant screen: roster,
player detail (top stats + counting stats + at-bat pad + game log),
auth splash, empty state, accent color, typography, icon. Bug fixes that
don't change visible pixels are exempt.

```bash
# 1. capture fresh raw sim screens (6.9" — iPhone 17 Pro Max)
BUNDLE=com.divinedavis.BaseballStatTracker
APP="$(xcodebuild -project BaseballStatTracker.xcodeproj \
  -showBuildSettings -configuration Debug -sdk iphonesimulator 2>/dev/null \
  | awk -F ' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')/BaseballStatTracker.app"
xcrun simctl terminate booted "$BUNDLE" 2>/dev/null
xcrun simctl uninstall booted "$BUNDLE" 2>/dev/null
xcrun simctl install booted "$APP"
xcrun simctl status_bar booted override --time "9:41" --dataNetwork wifi \
  --wifiBars 3 --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100
RAW=docs/marketing/raw
for args in "01_roster.png:-demoSeed" \
            "02_detail_top.png:-demoSeed -demoOpenDetail" \
            "03_expanded_stats.png:-demoSeed -demoOpenDetail -demoExpandStats" \
            "04_game_log.png:-demoSeed -demoOpenDetail -demoExpandStats -demoScrollGameLog"; do
  name="${args%%:*}"; flags="${args#*:}"
  xcrun simctl terminate booted "$BUNDLE" 2>/dev/null; sleep 0.3
  xcrun simctl launch booted "$BUNDLE" $flags >/dev/null
  sleep 2.2
  xcrun simctl io booted screenshot "$RAW/$name" >/dev/null
done

# 2. re-composite marketing frames (writes 6.9/ + 6.5/ sets)
python3 scripts/compose_marketing.py

# 3. re-upload to ASC (tears down + rebuilds both display sizes)
scripts/asc_publish_metadata.py
```

Ship the new TestFlight build in the same commit (Rule #1). If version
1.0 is in `WAITING_FOR_REVIEW` or `IN_REVIEW`, screenshot updates via the
API return `409 INVALID_STATE` — hold the recapture for the next editable
version (1.1), but still regenerate the raw + composed files locally and
commit them so the repo stays in lockstep with the UI.

---

## ⚑ Rule #2: KEEP THIS FILE LOADED WITH IMPORTANT INFORMATION

**Treat this file as the long-term memory for the project.** At the end of any session — or any time you learn something that would save a future session from re-discovering it — stop and ask: *is this worth writing down here?*

### What counts as "important information"

- **Gotchas and workarounds** — Apple API quirks (e.g. `POST /v1/apps` 403), simulator-only artifacts (Apple error 1000 on no-Apple-ID), provisioning / entitlement traps.
- **Invariants that aren't obvious from the code** — "slash line is locked open," "team field was intentionally removed," "`AtBatOutcome.stolenBase` does not increment AB," "`kSecAttrAccessibleAfterFirstUnlock` is chosen so sessions survive reinstall."
- **Cross-project distinctions** — this repo is *Baseball Stat Tracker* (`com.divinedavis.BaseballStatTracker`, ASC id `6762527182`, name "Bball Tracker"). Not Hidden Gems, not Clock-In, not ShypQuick, not HomeFinder NYC, not Polinear, not caprecruiting. The user keeps multiple iOS apps on their desktop; always confirm the working directory before diagnosing "doesn't work" reports.
- **Script behavior that's not self-evident** — what `ship-to-testflight.sh` bumps, what the `--auto-notes` flag does, the `scripts/.last-shipped-commit` marker, the fact that parallel ships deadlock if you queue them with `pgrep -f ship-to-testflight.sh` (the waiter matches itself).
- **Deliberate design calls the user made** — per-change TestFlight ships vs hourly cron, white auth sheet over cream, appearance picker in profile menu not detail view, silently swallowing Apple cancel errors.
- **Anything you had to read multiple files to figure out.** If the answer wasn't in this file, write it in.

### What *not* to put here

- Code snippets that mirror current source — the code is the source of truth. Reference file paths, not copies.
- Ephemeral task state — that's what commits and PR descriptions are for.
- Anything secret (see Rule #0).

### When in doubt

If you spent more than ~30 seconds figuring something out this session that another run will also need, it belongs here.

---

## 3. TestFlight ship pipeline

The ship pipeline (`scripts/ship-to-testflight.sh`) bumps `CURRENT_PROJECT_VERSION` by 1, regenerates the Xcode project, archives Release, exports, uploads via `altool`, and polls App Store Connect until the build is processed — then sets the "What to Test" notes from the git log.

**Hourly cron is disabled by choice.** The LaunchAgent (`com.divinedavis.baseballstattracker.testflight`) was removed on 2026-04-18. Ship per-change instead (Rule #1). The `install-testflight-cron.sh` / `uninstall-testflight-cron.sh` scripts and the `.plist` template are kept in `scripts/` in case we ever want to reinstate hourly batching.

### One-time setup

The only click-in-a-web-UI step is creating the ASC API key — API keys can't create themselves. Everything after that is automated by `scripts/bootstrap-app.py`.

1. **Create (or reuse) an App Store Connect API key.** If you already have one from another app in the same team (Clock-In, Hidden Gems, ShypQuick), **reuse it** — one key works across all apps on the team.

   Otherwise: Users and Access → Integrations → App Store Connect API → **"+"**, role **Admin** (needed for app creation; App Manager can only manage existing apps). Download the `.p8` once — Apple won't show it again.

   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
   chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
   ```

2. **Fill in the credentials file** (leave `ASC_APP_ID` as the placeholder — the bootstrap script will write it in):

   ```bash
   cp scripts/asc-config.env.example scripts/asc-config.env
   # edit scripts/asc-config.env — set:
   #   ASC_KEY_ID        (10-char key id)
   #   ASC_ISSUER_ID     (uuid from the top of the ASC API keys page)
   #   ASC_KEY_PATH      (~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8)
   #   ASC_TEAM_ID       (CG89RY4W6R)
   #   ASC_BUNDLE_ID=com.divinedavis.BaseballStatTracker
   #   ASC_APP_ID        (leave as 0000000000 — bootstrap-app.py fills it in)
   ```

3. **Bootstrap the bundle ID and app record**:

   ```bash
   pip3 install --user 'pyjwt[crypto]'    # once, if you haven't
   scripts/bootstrap-app.py
   ```

   This registers `com.divinedavis.BaseballStatTracker` in the Developer portal (fully automated) and stamps the resulting numeric `ASC_APP_ID` into `scripts/asc-config.env` once the app record exists. Re-runnable — it no-ops when everything's already there.

   **⚠ Apple limitation:** `POST /v1/apps` is not available on the App Store Connect API (returns `403 FORBIDDEN_ERROR` regardless of API key role). So the bootstrap script automates the bundle ID, but the app record itself has to be created in the web UI once. The script detects this case and prints exact step-by-step instructions when it happens. After clicking Create in the web UI, re-run `scripts/bootstrap-app.py` — it'll find the app and finish the wiring. If the name is taken on the App Store, pass `--name "Baseball Stats Tracker"` or similar on the retry.

4. **First ship**:

   ```bash
   scripts/ship-to-testflight.sh "Initial TestFlight build"
   ```

   After this, every change follows Rule #1: commit, push, and re-run `scripts/ship-to-testflight.sh --auto-notes`.

### Useful commands

```bash
# (optional, only if reinstating the hourly batch workflow)
#   scripts/install-testflight-cron.sh
#   launchctl print "gui/$(id -u)/com.divinedavis.baseballstattracker.testflight" | head -20

# tail the cron logs
tail -f scripts/.cron.out.log scripts/.cron.err.log

# force a ship right now (bypasses --if-changed)
scripts/ship-to-testflight.sh --auto-notes

# bump marketing version (e.g., 1.0 → 1.1)
scripts/ship-to-testflight.sh --marketing 1.1 "Release notes here"

# stop the hourly agent
scripts/uninstall-testflight-cron.sh
```

## 4. App icon

The placeholder at `BaseballStatTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is a vector silhouette. Replace it with a 1024×1024 photorealistic render in the Apple Liquid Glass style.

Suggested prompt for Midjourney / DALL·E / Firefly:

> Cinematic photorealistic iOS app icon, rounded square, a baseball player mid-swing hitting a baseball at the moment of contact, stadium lights flaring, deep navy and warm sunset orange glow, translucent Liquid Glass highlights, shallow depth of field, premium Apple App Store icon aesthetic, 1024×1024, centered composition, no text.

Save the result as `BaseballStatTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (exactly that filename; the Contents.json already references it). Commit and push — the next hourly build will ship the new icon.

## 5. Project structure

```
Baseball-Stat-Tracker/
├── BaseballStatTracker/
│   ├── BaseballStatTrackerApp.swift
│   ├── Models/Player.swift
│   ├── Stores/PlayerStore.swift
│   ├── Views/RootView.swift
│   ├── Views/PlayerRow.swift
│   ├── Views/PlayerDetailView.swift
│   ├── Views/AddPlayerView.swift
│   └── Assets.xcassets/
├── scripts/
│   ├── ship-to-testflight.sh
│   ├── install-testflight-cron.sh
│   ├── uninstall-testflight-cron.sh
│   ├── asc_set_whats_new.py
│   ├── asc-config.env.example
│   └── com.divinedavis.baseballstattracker.testflight.plist
├── project.yml           # xcodegen source of truth
├── README.md
└── INSTRUCTIONS.md       # this file
```

`BaseballStatTracker.xcodeproj` is generated from `project.yml` — don't edit it by hand. Run `xcodegen generate` after changing the project spec.
