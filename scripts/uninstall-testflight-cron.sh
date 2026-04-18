#!/usr/bin/env bash
# Remove the hourly TestFlight LaunchAgent.
set -euo pipefail

LABEL="com.divinedavis.baseballstattracker.testflight"
INSTALLED="$HOME/Library/LaunchAgents/${LABEL}.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$INSTALLED"
echo "✓ removed $INSTALLED and stopped $LABEL"
