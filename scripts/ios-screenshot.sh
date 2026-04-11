#!/usr/bin/env bash
# ios-screenshot.sh — capture a PNG of a named UI route from the running MTGScanner app.
#
# Usage:
#   ROUTE=settings ./scripts/ios-screenshot.sh settings
#   make ios-snapshot ROUTE=scan
#
# The script:
#   1. Resolves a simulator UDID (prefers IOS_SNAPSHOT_SIMULATOR_ID env var).
#   2. Boots the simulator if not already running.
#   3. Builds the app (via 'make ios-snapshot-build' or directly with xcodebuild).
#   4. Installs the built .app on the simulator.
#   5. Launches the app with -UI_PREVIEW_ROUTE <route>.
#   6. Waits for the UI to settle, then captures a screenshot.
#   7. Terminates the app.
#   8. Writes the PNG to services/.artifacts/ui-snapshots/<route>.png.
#
# Environment variables:
#   ROUTE                      — route name (default: settings)
#   IOS_SNAPSHOT_SIMULATOR_ID  — simulator UDID to use (optional)
#   IOS_SNAPSHOT_WAIT          — seconds to wait before screenshot (default: 3)

set -euo pipefail

ROUTE="${1:-${ROUTE:-settings}}"
WAIT="${IOS_SNAPSHOT_WAIT:-4}"
BUNDLE_ID="com.brettvitaz.mtgscanner"
WORKSPACE="apps/ios/MTGScanner.xcworkspace"
SCHEME="MTGScanner"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Resolve simulator UDID ────────────────────────────────────────────────────

if [[ -n "${IOS_SNAPSHOT_SIMULATOR_ID:-}" ]]; then
    SIM_UDID="$IOS_SNAPSHOT_SIMULATOR_ID"
else
    # Pick a booted simulator first; fall back to the first available iPhone.
    BOOTED_UDID=$(xcrun simctl list devices available | awk -F '[()]' '/\(Booted\)/ && /iPhone/ && $2 ~ /^[0-9A-F-]+$/ { print $2; exit }')
    if [[ -n "$BOOTED_UDID" ]]; then
        SIM_UDID="$BOOTED_UDID"
    else
        SIM_UDID=$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && $2 ~ /^[0-9A-F-]+$/ { print $2; exit }')
    fi
fi

if [[ -z "${SIM_UDID:-}" ]]; then
    echo "ios-screenshot: no available iPhone simulator found" >&2
    exit 1
fi
echo "ios-screenshot: using simulator $SIM_UDID"

# ── Boot simulator if needed ──────────────────────────────────────────────────

SIM_STATE=$(xcrun simctl list devices | grep "$SIM_UDID" | awk -F '[()]' '{ for(i=1;i<=NF;i++) if ($i ~ /Booted|Shutdown/) print $i }')
if [[ "$SIM_STATE" != "Booted" ]]; then
    echo "ios-screenshot: booting simulator $SIM_UDID ..."
    xcrun simctl boot "$SIM_UDID"
    xcrun simctl bootstatus "$SIM_UDID" -b
fi

# ── Locate the built .app ─────────────────────────────────────────────────────

cd "$REPO_ROOT"

BUILT_PRODUCTS_DIR=$(xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Debug \
    -showBuildSettings 2>/dev/null \
    | awk '/^ *BUILT_PRODUCTS_DIR =/ { sub(/.*= /, ""); print }')

APP_PATH="${BUILT_PRODUCTS_DIR}/MTGScanner.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "ios-screenshot: app not found at $APP_PATH — run 'make ios-build' first" >&2
    exit 1
fi
echo "ios-screenshot: installing $APP_PATH"

# ── Install and launch ────────────────────────────────────────────────────────

xcrun simctl install "$SIM_UDID" "$APP_PATH"

echo "ios-screenshot: launching with route '$ROUTE'"
# -FlagName value is converted to UserDefaults by iOS
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" -UI_PREVIEW_ROUTE "$ROUTE" > /dev/null

echo "ios-screenshot: waiting ${WAIT}s for UI to settle ..."
sleep "$WAIT"

# ── Screenshot ────────────────────────────────────────────────────────────────

OUT_DIR="${REPO_ROOT}/services/.artifacts/ui-snapshots"
mkdir -p "$OUT_DIR"
OUT_PATH="${OUT_DIR}/${ROUTE}.png"

xcrun simctl io "$SIM_UDID" screenshot "$OUT_PATH"
echo "ios-screenshot: saved $OUT_PATH"

# ── Terminate app ─────────────────────────────────────────────────────────────

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
