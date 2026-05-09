#!/bin/bash
set -e

VERSION=$(defaults read "$(pwd)/Info.plist" CFBundleShortVersionString)
APP_NAME="Tikatype"
APP_BUNDLE="/tmp/${APP_NAME}.app"
ZIP_NAME="${APP_NAME}-${VERSION}-app.zip"

echo "Building ${APP_NAME} ${VERSION}..."

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp .build/release/Tikatype "$APP_BUNDLE/Contents/MacOS/Tikatype"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

codesign --force --deep --sign - --identifier com.mmag.tikatype "$APP_BUNDLE"

cd /tmp
rm -f "$ZIP_NAME"
zip -r --symlinks "$ZIP_NAME" "${APP_NAME}.app"
SHA=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')

echo ""
echo "✓ Built: /tmp/${ZIP_NAME}"
echo "✓ SHA256: ${SHA}"
