#!/bin/zsh
# Runs an unsigned Debug Catalyst build under its own bundle identifier, so it
# keeps a sandbox container apart from an installed FlowDown and its data.
# With REAL_DATA=1 it first replaces the local database with a copy of the
# installed app's, so the build shows real conversations without touching them.

set -euo pipefail

BUILT_APP=${1:?usage: run-catalyst-local.sh <built FlowDown.app> <work dir>}
WORK_DIR=${2:?usage: run-catalyst-local.sh <built FlowDown.app> <work dir>}
BUNDLE_ID=wiki.qaq.flow.local
APP="$WORK_DIR/FlowDown Local.app"
ENTITLEMENTS="$WORK_DIR/local.entitlements"

pkill -f "$APP/Contents/MacOS/" || true
rm -rf "$APP"
mkdir -p "$WORK_DIR"
ditto "$BUILT_APP" "$APP"
rm -rf "$APP/Contents/PlugIns" "$APP/Contents/Extensions"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName FlowDown Local" "$APP/Contents/Info.plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string FlowDown Local" "$APP/Contents/Info.plist"

cat >"$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.get-task-allow</key>
	<true/>
</dict>
</plist>
PLIST

find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" \) -prune -print0 |
    xargs -0 -n 1 codesign --force --sign - --timestamp=none
codesign --force --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$APP"

if [ "${REAL_DATA:-0}" = "1" ]; then
    SOURCE_DB="$HOME/Library/Containers/wiki.qaq.flow/Data/Documents/Objects.db"
    LOCAL_DOCS="$HOME/Library/Containers/$BUNDLE_ID/Data/Documents"
    echo "copying database from installed app..."
    mkdir -p "$LOCAL_DOCS"
    rm -rf "$LOCAL_DOCS/Objects+Debug.db"
    ditto "$SOURCE_DB" "$LOCAL_DOCS/Objects+Debug.db"
fi

echo "[+] launching $APP"
open "$APP"
