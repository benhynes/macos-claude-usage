#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="ClaudeUsage.app"
BIN="$APP/Contents/MacOS/ClaudeUsage"

echo "Compiling…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O Sources/main.swift -o "$BIN" \
    -framework AppKit -framework Foundation

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClaudeUsage</string>
    <key>CFBundleDisplayName</key><string>Claude Usage</string>
    <key>CFBundleIdentifier</key><string>local.claudeusage</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>ClaudeUsage</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so the Keychain item ACL stays stable across rebuilds.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
echo "Run with:  open $APP   (or ./build.sh && open $APP)"
