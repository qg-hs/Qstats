#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

ARCH="${1:-}"
case "$ARCH" in
    arm64)
        CHIP_NAME="apple-silicon"
        ;;
    x86_64)
        CHIP_NAME="intel"
        ;;
    *)
        echo "Usage: ./package.sh <arm64|x86_64>" >&2
        exit 2
        ;;
esac

APP_NAME="Qstats"
BUNDLE_ID="com.qghs.Qstats"
VERSION="$(tr -d '[:space:]' < VERSION)"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}-${CHIP_NAME}.dmg"
CHECKSUM_NAME="SHA256SUMS-${ARCH}.txt"
PACKAGE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/Qstats-package.XXXXXX")"
trap 'rm -rf "$PACKAGE_TMP"' EXIT

export MACOSX_DEPLOYMENT_TARGET=13.0
swift build -c release --arch "$ARCH"
BUILD_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
test "$(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")" = "$ARCH"

ICONSET="$PACKAGE_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 qghs. MIT License.</string>
</dict></plist>
PLIST
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
codesign --force -s - -i "${BUNDLE_ID}" -r="designated => identifier \"${BUNDLE_ID}\"" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

STAGING="$PACKAGE_TMP/dmg"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_NAME" "$CHECKSUM_NAME"
hdiutil create -volname "Qstats ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG_NAME"
shasum -a 256 "$DMG_NAME" > "$CHECKSUM_NAME"
printf 'Created %s (%s)\n' "$DMG_NAME" "$ARCH"
