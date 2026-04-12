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
#   3. Locates the pre-built .app produced by a prior build.
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
if [[ ! "$ROUTE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "ios-screenshot: invalid route name '$ROUTE' — only alphanumeric, hyphens, and underscores allowed" >&2
    exit 1
fi
# scan route needs a longer settle time for the detection overlay to appear.
# Override with IOS_SNAPSHOT_WAIT=<seconds> if needed.
if [[ "$ROUTE" == "scan" ]]; then
    WAIT="${IOS_SNAPSHOT_WAIT:-5}"
else
    WAIT="${IOS_SNAPSHOT_WAIT:-4}"
fi
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

# ── Locate the built .app and resolve bundle ID ───────────────────────────────

cd "$REPO_ROOT"

BUILD_SETTINGS=$(xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Debug \
    -showBuildSettings 2>/dev/null)

BUILT_PRODUCTS_DIR=$(echo "$BUILD_SETTINGS" | awk '/^ *BUILT_PRODUCTS_DIR =/ { sub(/.*= /, ""); print; exit }')
FULL_PRODUCT_NAME=$(echo "$BUILD_SETTINGS" | awk '/^ *FULL_PRODUCT_NAME =/ { sub(/.*= /, ""); print; exit }')
BUNDLE_ID=$(echo "$BUILD_SETTINGS" | awk '/^ *PRODUCT_BUNDLE_IDENTIFIER =/ { sub(/.*= /, ""); print; exit }')

if [[ -z "${BUILT_PRODUCTS_DIR:-}" ]]; then
    echo "ios-screenshot: could not read BUILT_PRODUCTS_DIR from xcodebuild" >&2
    exit 1
fi

if [[ -z "${FULL_PRODUCT_NAME:-}" ]]; then
    echo "ios-screenshot: could not read FULL_PRODUCT_NAME from xcodebuild" >&2
    exit 1
fi

if [[ -z "${BUNDLE_ID:-}" ]]; then
    echo "ios-screenshot: could not read PRODUCT_BUNDLE_IDENTIFIER from xcodebuild" >&2
    exit 1
fi

APP_PATH="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"

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

# ── Terminate app and clean up UserDefaults ───────────────────────────────────

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
# Remove the preview-route key so normal (non-snapshot) launches of the app on this
# simulator are not accidentally routed to the preview host.
xcrun simctl spawn "$SIM_UDID" defaults delete "$BUNDLE_ID" UI_PREVIEW_ROUTE 2>/dev/null || true
