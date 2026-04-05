#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NOU"
BUNDLE_ID="com.enablerdao.nou"
VERSION="${1:-2.0}"
BUILD_DIR=".build/release"

echo "=== Building $APP_NAME v$VERSION ==="

# Build release binary
swift build -c release 2>&1

BINARY="$BUILD_DIR/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

# Create .app bundle
APP_DIR="$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy icon if available
ICON_SRC="../Sources/App/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
if [ -f "$ICON_SRC" ] && command -v iconutil &>/dev/null; then
    ICONSET=$(mktemp -d)/NOU.iconset
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" &>/dev/null
        s2=$((s*2)); sips -z $s2 $s2 "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" &>/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "  Icon: AppIcon.icns generated"
fi

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSBonjourServices</key>
    <array>
        <string>_nou._tcp</string>
    </array>
    <key>NSLocalNetworkUsageDescription</key>
    <string>NOU discovers other AI nodes on your local network.</string>
</dict>
</plist>
PLIST

echo "=== $APP_DIR created ==="
echo "  Binary: $(du -sh "$APP_DIR/Contents/MacOS/$APP_NAME" | cut -f1)"
echo "  Run:    open $APP_DIR"
