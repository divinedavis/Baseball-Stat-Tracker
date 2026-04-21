#!/usr/bin/env bash
# Ship a new TestFlight build end-to-end:
#   - bump CURRENT_PROJECT_VERSION in project.yml
#   - xcodegen generate
#   - archive (Release, automatic signing)
#   - export for App Store Connect distribution
#   - upload via altool
#   - poll until processing completes
#   - set "What to Test" release notes via App Store Connect API
#   - record the shipped git commit so future --if-changed runs can no-op
#
# Usage:
#   scripts/ship-to-testflight.sh "release notes text (supports \n for newlines)"
#   scripts/ship-to-testflight.sh --marketing 1.2 "release notes for the 1.2 train"
#   scripts/ship-to-testflight.sh --if-changed          # skip if HEAD == last shipped
#   scripts/ship-to-testflight.sh --if-changed --auto-notes
#
# --if-changed     : exit 0 without shipping when HEAD == last shipped commit.
# --auto-notes     : release notes become `git log --oneline <last>..HEAD` formatted
#                    as a bulleted list. Useful for the hourly cron; falls back to
#                    "Automated build — <short-sha>" if no prior marker exists.
# --marketing X.Y  : bump MARKETING_VERSION to X.Y before archiving.
#
# Credentials come from scripts/asc-config.env (gitignored).
# Copy scripts/asc-config.env.example to scripts/asc-config.env and fill in values.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SCRIPT_DIR/asc-config.env"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "▸ $*"; }

[[ -f "$CONFIG" ]] || die "$CONFIG not found. Copy asc-config.env.example and fill in values."
# shellcheck disable=SC1090
source "$CONFIG"

: "${ASC_KEY_ID:?ASC_KEY_ID must be set in asc-config.env}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID must be set in asc-config.env}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH must be set in asc-config.env}"
: "${ASC_TEAM_ID:?ASC_TEAM_ID must be set in asc-config.env}"
: "${ASC_APP_ID:?ASC_APP_ID must be set in asc-config.env}"
ASC_KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
[[ -f "$ASC_KEY_PATH" ]] || die "ASC_KEY_PATH does not exist: $ASC_KEY_PATH"

cd "$PROJECT_ROOT"

# Default scheme/project derived from project.yml if not overridden
SCHEME="${ASC_SCHEME:-$(awk -F': ' '/^name:/ {print $2; exit}' project.yml)}"
PROJECT="${ASC_PROJECT:-${SCHEME}.xcodeproj}"
[[ -n "$SCHEME" ]] || die "could not determine scheme — set ASC_SCHEME in asc-config.env"
[[ -d "$PROJECT" ]] || die "project not found: $PROJECT (regenerate with xcodegen?)"

# Parse args
NEW_MARKETING=""
IF_CHANGED=0
AUTO_NOTES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --marketing)
            NEW_MARKETING="$2"; shift 2;;
        --if-changed)
            IF_CHANGED=1; shift;;
        --auto-notes)
            AUTO_NOTES=1; shift;;
        -h|--help)
            sed -n '2,30p' "$0"; exit 0;;
        -*)
            die "unknown flag: $1";;
        *)
            WHATS_NEW="$1"; shift;;
    esac
done

MARKER="$SCRIPT_DIR/.last-shipped-commit"
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || true)
[[ -n "$HEAD_SHA" ]] || die "not inside a git repo — ship script requires git"

# Paths whose changes actually affect the built IPA. Commits that only touch docs,
# scripts, CI configs, etc. produce a byte-identical app and are skipped in --if-changed mode.
BUILD_PATHS=(BaseballStatTracker project.yml)

if (( IF_CHANGED )) && [[ -f "$MARKER" ]]; then
    LAST_SHA=$(cat "$MARKER")
    if [[ "$LAST_SHA" == "$HEAD_SHA" ]]; then
        info "no new commits since last shipped ($LAST_SHA). skipping."
        exit 0
    fi
    if git diff --quiet "${LAST_SHA}..HEAD" -- "${BUILD_PATHS[@]}"; then
        info "no build-affecting changes in ${BUILD_PATHS[*]} since $LAST_SHA. skipping."
        echo "$HEAD_SHA" > "$MARKER"
        exit 0
    fi
fi

# Generate release notes from git log if --auto-notes requested.
if (( AUTO_NOTES )) && [[ -z "${WHATS_NEW:-}" ]]; then
    if [[ -f "$MARKER" ]]; then
        LAST_SHA=$(cat "$MARKER")
        WHATS_NEW=$(git log --pretty=format:"- %s" "${LAST_SHA}..HEAD" 2>/dev/null || echo "")
    fi
    if [[ -z "${WHATS_NEW:-}" ]]; then
        WHATS_NEW="Automated build — $(git rev-parse --short HEAD)"
    fi
fi

[[ -n "${WHATS_NEW:-}" ]] || die "missing release notes. usage: $0 \"notes\" (or --auto-notes)"

# ---------- bump version numbers ----------
CURRENT_BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
NEXT_BUILD=$((CURRENT_BUILD + 1))
info "build: $CURRENT_BUILD → $NEXT_BUILD"
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT_BUILD\"/CURRENT_PROJECT_VERSION: \"$NEXT_BUILD\"/" project.yml

if [[ -n "$NEW_MARKETING" ]]; then
    OLD_MARKETING=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
    info "marketing: $OLD_MARKETING → $NEW_MARKETING"
    /usr/bin/sed -i '' "s/MARKETING_VERSION: \"$OLD_MARKETING\"/MARKETING_VERSION: \"$NEW_MARKETING\"/" project.yml
fi
MARKETING=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)

info "regenerating Xcode project"
xcodegen generate >/dev/null

# Strip extended attributes (com.apple.FinderInfo etc.) from sources and project.
# macOS Finder can silently attach these, which makes codesign refuse the bundle
# with "resource fork, Finder information, or similar detritus not allowed".
info "stripping extended attributes from sources"
xattr -rc "$PROJECT_ROOT/BaseballStatTracker" 2>/dev/null || true
xattr -rc "$PROJECT_ROOT/$PROJECT" 2>/dev/null || true
xattr -c  "$PROJECT_ROOT/project.yml" 2>/dev/null || true

# ---------- archive ----------
ARCHIVE=/tmp/${SCHEME}-ship.xcarchive
EXPORT_DIR=/tmp/${SCHEME}-ship-export
rm -rf "$ARCHIVE" "$EXPORT_DIR"

archive_once() {
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "$ARCHIVE" \
        -allowProvisioningUpdates \
        -authenticationKeyPath "$ASC_KEY_PATH" \
        -authenticationKeyID "$ASC_KEY_ID" \
        -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
        archive >/tmp/ship-archive.log 2>&1
}

info "archiving ${MARKETING} (${NEXT_BUILD})"
if ! archive_once; then
    if grep -q "resource fork, Finder information" /tmp/ship-archive.log 2>/dev/null; then
        info "codesign hit xattr detritus — stripping archive + retrying"
        [[ -d "$ARCHIVE" ]] && xattr -rc "$ARCHIVE" 2>/dev/null || true
        rm -rf "$ARCHIVE"
        archive_once || { tail -40 /tmp/ship-archive.log; die "archive failed even after xattr cleanup — see /tmp/ship-archive.log"; }
    else
        tail -40 /tmp/ship-archive.log; die "archive failed — see /tmp/ship-archive.log"
    fi
fi

# ---------- export ----------
EXPORT_OPTS=/tmp/ship-ExportOptions.plist
cat > "$EXPORT_OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>$ASC_TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>destination</key><string>export</string>
</dict>
</plist>
EOF

info "exporting"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" >/tmp/ship-export.log 2>&1 \
    || { tail -40 /tmp/ship-export.log; die "export failed — see /tmp/ship-export.log"; }

IPA=$(ls "$EXPORT_DIR"/*.ipa | head -1)
[[ -f "$IPA" ]] || die "no .ipa produced in $EXPORT_DIR"

# ---------- upload ----------
info "uploading $(basename "$IPA")"
xcrun altool --upload-app \
    -f "$IPA" \
    -t ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    --output-format json >/tmp/ship-upload.log 2>&1 \
    || { cat /tmp/ship-upload.log; die "upload failed"; }

# ---------- poll & set release notes ----------
info "waiting for processing + setting release notes"
python3 "$SCRIPT_DIR/asc_set_whats_new.py" \
    --app-id "$ASC_APP_ID" \
    --version "$MARKETING" \
    --build "$NEXT_BUILD" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --key-path "$ASC_KEY_PATH" \
    --whats-new "$WHATS_NEW"

echo "$HEAD_SHA" > "$MARKER"
info "✓ shipped ${MARKETING} (${NEXT_BUILD}) — marker updated to $HEAD_SHA"
