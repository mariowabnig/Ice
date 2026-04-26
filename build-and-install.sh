#!/bin/bash
set -euo pipefail

echo "=== Building Ice ==="
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
  DEBUG_INFORMATION_FORMAT=dwarf \
  build 2>&1 | tail -3

echo "=== Stopping Ice ==="
pkill -x Ice 2>/dev/null || true
sleep 1

echo "=== Installing ==="
rm -rf /Applications/Ice.app
cp -R build/Build/Products/Release/Ice.app /Applications/Ice.app
codesign --force --sign - --timestamp=none /Applications/Ice.app/Contents/Frameworks/Sparkle.framework 2>/dev/null
codesign --force --sign - --timestamp=none /Applications/Ice.app 2>/dev/null

echo "=== Launching ==="
open /Applications/Ice.app

echo "=== Done! Existing permissions were left in place ==="
