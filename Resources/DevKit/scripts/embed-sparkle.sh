#!/bin/zsh
# Copies Sparkle.framework into a built Mac Catalyst app. A Catalyst target
# cannot link the AppKit framework, so the app loads it at launch instead
# (see SparkleUpdater.swift). Sign the app after this runs.

set -euo pipefail

APP=${1:?usage: embed-sparkle.sh <FlowDown.app>}
SPARKLE_VERSION=2.10.1
SPARKLE_SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
CACHE=${SPARKLE_CACHE:-$HOME/Library/Caches/FlowDown/Sparkle-$SPARKLE_VERSION}
ARCHIVE="$CACHE/Sparkle-$SPARKLE_VERSION.tar.xz"

if [[ ! -d "$CACHE/Sparkle.framework" ]]; then
    echo "downloading sparkle $SPARKLE_VERSION..."
    mkdir -p "$CACHE"
    curl -fsSL -o "$ARCHIVE" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
    echo "$SPARKLE_SHA256  $ARCHIVE" | shasum -a 256 -c -
    tar -xf "$ARCHIVE" -C "$CACHE" Sparkle.framework
fi

mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$CACHE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
echo "[+] embedded sparkle $SPARKLE_VERSION in $APP"
