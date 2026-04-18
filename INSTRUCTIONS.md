# Baseball Stat Tracker — Workflow Instructions

This file is the source of truth for how we work on this app. Claude reads it at the start of each session.

## 1. GitHub: push after every change

- Remote: `git@github.com:divinedavis/Baseball-Stat-Tracker.git`
- Branch: `main`
- After **every** code or asset change, commit and push:

  ```bash
  git add -A
  git commit -m "<concise imperative subject>"
  git push origin main
  ```

- One meaningful commit per logical change (don't batch unrelated edits). The hourly TestFlight LaunchAgent reads `origin/main`, so a missed push means a missed build.

## 2. Hourly TestFlight builds (build number bumps like .1, .2, .3…)

The ship pipeline (`scripts/ship-to-testflight.sh`) bumps `CURRENT_PROJECT_VERSION` by 1, regenerates the Xcode project, archives Release, exports, uploads via `altool`, and polls App Store Connect until the build is processed — then sets the "What to Test" notes from the git log.

A user LaunchAgent (`com.divinedavis.baseballstattracker.testflight`) fires every `3600s` and invokes the script with `--if-changed --auto-notes`, so:
- If there are no new commits since the last shipped build → exit 0, nothing happens.
- If only docs/scripts changed → exit 0, marker advances, no upload.
- If `BaseballStatTracker/` or `project.yml` changed → a new build ships automatically.

### One-time setup

1. **Create the app record in App Store Connect** with bundle ID `com.divinedavis.BaseballStatTracker`. Grab the numeric App ID from the URL after creating it.

2. **Create an App Store Connect API key** (Users and Access → Integrations → App Store Connect API, role: App Manager). Download the `.p8`.

   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
   chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
   ```

3. **Fill in credentials**:

   ```bash
   cp scripts/asc-config.env.example scripts/asc-config.env
   # edit scripts/asc-config.env — set ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH,
   # ASC_TEAM_ID (CG89RY4W6R), ASC_APP_ID (the numeric id from step 1),
   # ASC_BUNDLE_ID=com.divinedavis.BaseballStatTracker
   ```

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
