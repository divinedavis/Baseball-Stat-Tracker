#!/usr/bin/env bash
# Install the hourly TestFlight LaunchAgent for this repo.
# Re-run after moving the repo — the plist has the project path baked in.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/com.divinedavis.baseballstattracker.testflight.plist"
LABEL="com.divinedavis.baseballstattracker.testflight"
INSTALLED="$HOME/Library/LaunchAgents/${LABEL}.plist"

[[ -f "$TEMPLATE" ]] || { echo "error: $TEMPLATE not found"; exit 1; }
[[ -f "$SCRIPT_DIR/asc-config.env" ]] || { echo "error: scripts/asc-config.env missing — copy from asc-config.env.example first"; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents"
sed "s|{{PROJECT_ROOT}}|$PROJECT_ROOT|g" "$TEMPLATE" > "$INSTALLED"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$INSTALLED"
launchctl enable "gui/$(id -u)/$LABEL"

echo "✓ installed $INSTALLED"
echo "  label: $LABEL"
echo "  runs every 3600s; logs → scripts/.cron.{out,err}.log"
echo "  status: launchctl print gui/$(id -u)/$LABEL | head -20"
