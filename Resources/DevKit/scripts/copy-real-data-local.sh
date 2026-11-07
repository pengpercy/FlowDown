#!/bin/zsh
# Replaces the local Debug build's database with a copy of the installed
# FlowDown's, so it shows real conversations without writing to them.

set -euo pipefail

BUNDLE_ID=wiki.qaq.flow.local
SOURCE_DB="$HOME/Library/Containers/wiki.qaq.flow/Data/Documents/Objects.db"
LOCAL_DOCS="$HOME/Library/Containers/$BUNDLE_ID/Data/Documents"

osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null || true
if pgrep -f "/Applications/FlowDown.app/Contents/MacOS/" >/dev/null; then
    echo "[*] the installed FlowDown is running; the copy may miss its latest writes"
fi
mkdir -p "$LOCAL_DOCS"
rm -rf "$LOCAL_DOCS/Objects+Debug.db"
ditto "$SOURCE_DB" "$LOCAL_DOCS/Objects+Debug.db"
echo "[+] copied database to $LOCAL_DOCS/Objects+Debug.db"
