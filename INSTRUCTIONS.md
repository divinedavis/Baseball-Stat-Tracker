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

## ⚑ Rule #1: PUSH TO GITHUB AFTER EVERY CHANGE

**Non-negotiable.** After *every* code, asset, script, or doc change — no matter how small — commit and push to `origin main` on `git@github.com:divinedavis/Baseball-Stat-Tracker.git`.

```bash
git add -A
git commit -m "<concise imperative subject>"
git push origin main
```

If the push fails (repo doesn't exist, no auth, network), **stop and surface it immediately** — don't keep editing locally. The hourly TestFlight LaunchAgent reads `origin/main`, so an unpushed commit = a missed build.

One meaningful commit per logical change. Don't batch unrelated edits.

## 2. Hourly TestFlight builds (build number bumps like .1, .2, .3…)

The ship pipeline (`scripts/ship-to-testflight.sh`) bumps `CURRENT_PROJECT_VERSION` by 1, regenerates the Xcode project, archives Release, exports, uploads via `altool`, and polls App Store Connect until the build is processed — then sets the "What to Test" notes from the git log.

A user LaunchAgent (`com.divinedavis.baseballstattracker.testflight`) fires every `3600s` and invokes the script with `--if-changed --auto-notes`, so:
- If there are no new commits since the last shipped build → exit 0, nothing happens.
- If only docs/scripts changed → exit 0, marker advances, no upload.
- If `BaseballStatTracker/` or `project.yml` changed → a new build ships automatically.

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

4. **Install the hourly LaunchAgent**:

   ```bash
   scripts/install-testflight-cron.sh
   ```

5. **First manual ship** (sanity check — do this before trusting the cron):

   ```bash
   scripts/ship-to-testflight.sh "Initial TestFlight build"
   ```

### Useful commands

```bash
# see the launchd status
launchctl print "gui/$(id -u)/com.divinedavis.baseballstattracker.testflight" | head -20

# tail the cron logs
tail -f scripts/.cron.out.log scripts/.cron.err.log

# force a ship right now (bypasses --if-changed)
scripts/ship-to-testflight.sh --auto-notes

# bump marketing version (e.g., 1.0 → 1.1)
scripts/ship-to-testflight.sh --marketing 1.1 "Release notes here"

# stop the hourly agent
scripts/uninstall-testflight-cron.sh
```

## 3. App icon

The placeholder at `BaseballStatTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png` is a vector silhouette. Replace it with a 1024×1024 photorealistic render in the Apple Liquid Glass style.

Suggested prompt for Midjourney / DALL·E / Firefly:

> Cinematic photorealistic iOS app icon, rounded square, a baseball player mid-swing hitting a baseball at the moment of contact, stadium lights flaring, deep navy and warm sunset orange glow, translucent Liquid Glass highlights, shallow depth of field, premium Apple App Store icon aesthetic, 1024×1024, centered composition, no text.

Save the result as `BaseballStatTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (exactly that filename; the Contents.json already references it). Commit and push — the next hourly build will ship the new icon.

## 4. Project structure

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
