#!/bin/zsh
# Runs an unsigned Debug Catalyst build under its own bundle identifier, so it
# keeps a sandbox container apart from an installed FlowDown and its data.
# With REAL_DATA=1 it first replaces the local database with a copy of the
# installed app's, so the build shows real conversations without touching them.

set -euo pipefail

BUILT_APP=${1:?usage: run-catalyst-local.sh <built FlowDown.app> <work dir>}
WORK_DIR=${2:?usage: run-catalyst-local.sh <built FlowDown.app> <work dir>}
SCRIPTS=${0:A:h}
BUNDLE_ID=wiki.qaq.flow.local
APP="$WORK_DIR/FlowDown Local.app"

osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$WORK_DIR"
ditto "$BUILT_APP" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
"$SCRIPTS/embed-sparkle.sh" "$APP"
"$SCRIPTS/sign-catalyst-local.sh" "$APP"

if [ "${REAL_DATA:-0}" = "1" ]; then
    "$SCRIPTS/copy-real-data-local.sh"
fi

echo "[+] launching $APP"
open "$APP"
