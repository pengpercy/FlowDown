#!/bin/zsh
# Writes git-ignored local settings so Xcode can run the Mac Catalyst Debug
# build on a Mac without the team's signing: it signs to run locally under its
# own bundle identifier, with only the entitlements an ad-hoc signature may
# carry, so it keeps a sandbox container apart from an installed FlowDown.

set -euo pipefail

ROOT=${0:A:h:h:h:h}
CONFIG="$ROOT/FlowDown/Configuration/DevelopmentDeveloper.xcconfig"
ENTITLEMENTS="$ROOT/FlowDown/Configuration/DevelopmentDeveloper.entitlements"

cat >"$CONFIG" <<'XCCONFIG'
//
//  DevelopmentDeveloper.xcconfig
//  FlowDown
//
//  Local only (git-ignored), written by `make setup-local-xcode`.
//  Runs the Mac Catalyst Debug build without the team's signing.
//

PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*] = wiki.qaq.flow.local
DEVELOPMENT_TEAM[sdk=macosx*] =
CODE_SIGN_STYLE[sdk=macosx*] = Manual
CODE_SIGN_IDENTITY[sdk=macosx*] = -
PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*] =
FLOWDOWN_CATALYST_ENTITLEMENTS = FlowDown/Configuration/DevelopmentDeveloper.entitlements
XCCONFIG

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

echo "[+] wrote $CONFIG"
echo "[+] wrote $ENTITLEMENTS"
