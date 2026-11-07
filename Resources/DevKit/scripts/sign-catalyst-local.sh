#!/bin/zsh
# Ad-hoc signs a Debug Catalyst app with only the entitlements it needs to run
# on a Mac without the team's provisioning profile: the sandbox, network and
# user-selected files, plus get-task-allow so a debugger can attach.

set -euo pipefail

APP=${1:?usage: sign-catalyst-local.sh <FlowDown.app>}
ENTITLEMENTS=$(mktemp -t flowdown-local-entitlements)

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

rm -rf "$APP/Contents/PlugIns" "$APP/Contents/Extensions"
find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" \) -prune -print0 |
    xargs -0 -n 1 codesign --force --sign - --timestamp=none 2>&1 |
    grep -v "replacing existing signature" || true
codesign --force --sign - --timestamp=none --entitlements "$ENTITLEMENTS" "$APP"
rm -f "$ENTITLEMENTS"
echo "[+] signed $APP"
