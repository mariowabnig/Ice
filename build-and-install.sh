#!/bin/bash
set -e

echo "=== Building Ice ==="
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
  build 2>&1 | tail -3

echo "=== Stopping Ice ==="
pkill -x Ice 2>/dev/null || true
sleep 1

echo "=== Resetting TCC permissions ==="
tccutil reset Accessibility com.jordanbaird.Ice 2>/dev/null
tccutil reset ScreenCapture com.jordanbaird.Ice 2>/dev/null

echo "=== Installing ==="
rm -rf /Applications/Ice.app
cp -R build/Build/Products/Release/Ice.app /Applications/Ice.app
codesign --force --deep --sign - /Applications/Ice.app 2>/dev/null

echo "=== Launching ==="
open /Applications/Ice.app

echo "=== Done! Grant accessibility permission when prompted ==="
