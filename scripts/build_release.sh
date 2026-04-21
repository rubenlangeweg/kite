#!/bin/bash
# Build Kite.app for Release. Outputs to build/Build/Products/Release/Kite.app.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

xcodegen generate

BUILD_DIR="$(pwd)/build"
rm -rf "$BUILD_DIR"

xcodebuild \
  -scheme Kite \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS' \
  clean build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES

APP_PATH="$BUILD_DIR/Build/Products/Release/Kite.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build did not produce expected .app at $APP_PATH" >&2
  exit 1
fi

# Ensure ad-hoc signature, honoring Kite.entitlements (sandbox off).
codesign --force --sign - --deep --entitlements Kite.entitlements "$APP_PATH"

echo ""
echo "=== Release build summary ==="
echo "Path:  $APP_PATH"
du -sh "$APP_PATH"
codesign -dv "$APP_PATH" 2>&1 | grep -E "Identifier|Format|Signature"
echo "=== Ready to install: drag to /Applications ==="
