#!/usr/bin/env bash
# Run the full XCTest + XCUITest suite for Barrel.
#
# Defaults:
#   - Project: BaseballStatTracker.xcodeproj (regenerated if stale)
#   - Scheme:  BaseballStatTracker
#   - Sim:     iPhone 17 (booted automatically by xcodebuild)
#
# Flags:
#   --unit-only       skip the XCUITest target (faster — under a second)
#   --ui-only         skip the unit target
#   --device <name>   override the simulator name
#   --verbose         echo full xcodebuild output
#
# Exit code matches xcodebuild — non-zero if any test fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

DEVICE="iPhone 17"
RUN_UNIT=1
RUN_UI=1
VERBOSE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --unit-only) RUN_UI=0; shift;;
        --ui-only)   RUN_UNIT=0; shift;;
        --device)    DEVICE="$2"; shift 2;;
        --verbose)   VERBOSE=1; shift;;
        -h|--help)
            sed -n '2,16p' "$0"; exit 0;;
        *) echo "unknown flag: $1" >&2; exit 2;;
    esac
done

info() { echo "▸ $*"; }

# Regenerate project if project.yml is newer than the .xcodeproj.
if [[ project.yml -nt BaseballStatTracker.xcodeproj/project.pbxproj ]]; then
    info "regenerating Xcode project (project.yml is newer)"
    xcodegen generate >/dev/null
fi

XCB_FLAGS=(
    -project BaseballStatTracker.xcodeproj
    -scheme BaseballStatTracker
    -destination "platform=iOS Simulator,name=$DEVICE"
    -configuration Debug
)

OUT_FILTER='cat'
if [[ "$VERBOSE" -eq 0 ]]; then
    OUT_FILTER='grep -E "Test Case|Test Suite|failed|error:|TEST.*(SUCCEEDED|FAILED)" || true'
fi

info "building for testing"
if [[ "$VERBOSE" -eq 1 ]]; then
    xcodebuild "${XCB_FLAGS[@]}" build-for-testing
else
    xcodebuild "${XCB_FLAGS[@]}" build-for-testing 2>&1 | tail -3
fi

ONLY_FLAGS=()
if [[ "$RUN_UNIT" -eq 1 && "$RUN_UI" -eq 1 ]]; then
    info "running unit + UI tests"
elif [[ "$RUN_UNIT" -eq 1 ]]; then
    info "running unit tests only"
    ONLY_FLAGS=(-only-testing:BaseballStatTrackerTests)
else
    info "running UI tests only"
    ONLY_FLAGS=(-only-testing:BaseballStatTrackerUITests)
fi

run_xcodebuild_test() {
    set +e
    xcodebuild "${XCB_FLAGS[@]}" ${ONLY_FLAGS[@]+"${ONLY_FLAGS[@]}"} test-without-building 2>&1 | eval "$OUT_FILTER"
    local status=${PIPESTATUS[0]}
    set -e
    return "$status"
}

if run_xcodebuild_test; then
    info "✓ all tests passed"
    exit 0
fi

# UI tests are environment-flaky — the simulator goes catatonic if it's
# been booted for a while. Cold-boot it and retry exactly once before
# reporting failure to the caller.
if [[ "$RUN_UI" -eq 1 ]]; then
    info "first attempt failed — cold-rebooting the simulator and retrying"
    pkill -f "BaseballStatTrackerUITests" 2>/dev/null || true
    xcrun simctl shutdown all >/dev/null 2>&1 || true
    sleep 2
    xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
    if run_xcodebuild_test; then
        info "✓ all tests passed (after retry)"
        exit 0
    fi
fi

info "✗ tests FAILED"
exit 1
