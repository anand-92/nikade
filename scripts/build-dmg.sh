#!/bin/bash
set -euo pipefail

# Configuration
APP_NAME="openOwl"
DISPLAY_NAME="OpenOwl"
SCHEME="openOwl"
SIGNING_IDENTITY="Developer ID Application: LU CANWEI (C3NL524YS6)"
TEAM_ID="C3NL524YS6"

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$DISPLAY_NAME.dmg"

# Read version from project.yml
VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
BUILD_NUM=$(grep 'CURRENT_PROJECT_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
DMG_FINAL="$BUILD_DIR/${DISPLAY_NAME}-${VERSION}.dmg"

echo "=== Building $DISPLAY_NAME v$VERSION (build $BUILD_NUM) ==="
echo ""

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Generate Xcode project
echo ">>> Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

# Step 2: Archive
echo ">>> Archiving..."
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--options=runtime" \
    | tail -5

# Step 3: Export archive
echo ">>> Exporting archive..."
mkdir -p "$EXPORT_PATH"

# Create export options plist
cat > "$BUILD_DIR/export-options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$BUILD_DIR/export-options.plist" \
    -exportPath "$EXPORT_PATH" \
    | tail -5

# Verify the exported app exists
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Exported app not found at $APP_PATH"
    echo "Looking for app in export path:"
    ls -la "$EXPORT_PATH/"
    exit 1
fi

# Step 4: Verify code signature
echo ""
echo ">>> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -3
echo "Signing identity:"
codesign -dvv "$APP_PATH" 2>&1 | grep "Authority"

# Step 5: Create DMG
echo ""
echo ">>> Creating DMG..."
rm -f "$DMG_PATH" "$DMG_FINAL"

# Create a temporary DMG folder with app and Applications symlink
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_FINAL"

rm -rf "$DMG_STAGING"

# Step 6: Sign the DMG
echo ""
echo ">>> Signing DMG..."
codesign --sign "$SIGNING_IDENTITY" "$DMG_FINAL"

# Step 7: Notarize (optional — requires App Store Connect API key)
echo ""
echo ">>> DMG ready at: $DMG_FINAL"
echo ""
ls -lh "$DMG_FINAL"
echo ""
echo "To notarize (optional):"
echo "  xcrun notarytool submit \"$DMG_FINAL\" --apple-id YOUR_APPLE_ID --password YOUR_APP_PASSWORD --team-id $TEAM_ID --wait"
echo "  xcrun stapler staple \"$DMG_FINAL\""
echo ""
echo "=== Done ==="
