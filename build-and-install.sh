#!/bin/bash
set -euo pipefail

SIGNING_IDENTITY_NAME="Ice Local Development"
SIGNING_IDENTITY="-"
LOGIN_KEYCHAIN="$(security default-keychain -d user 2>/dev/null | tr -d '"' || true)"
LOGIN_KEYCHAIN="${LOGIN_KEYCHAIN:-${HOME}/Library/Keychains/login.keychain-db}"

find_local_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null |
    awk -v name="$SIGNING_IDENTITY_NAME" '$0 ~ "\"" name "\"" { print $2; exit }'
}

cleanup_and_fail() {
  rm -rf "$1"
  return 1
}

create_local_signing_identity() {
  if ! command -v openssl >/dev/null 2>&1; then
    echo "  WARN: openssl not found; falling back to ad-hoc signing."
    return 1
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"

  local key_path="$tmpdir/ice-local-dev.key"
  local cert_path="$tmpdir/ice-local-dev.crt"
  local p12_path="$tmpdir/ice-local-dev.p12"

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -days 3650 \
    -nodes \
    -keyout "$key_path" \
    -out "$cert_path" \
    -subj "/CN=${SIGNING_IDENTITY_NAME}" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1 || cleanup_and_fail "$tmpdir"

  openssl pkcs12 \
    -export \
    -inkey "$key_path" \
    -in "$cert_path" \
    -out "$p12_path" \
    -name "$SIGNING_IDENTITY_NAME" \
    -passout pass: >/dev/null 2>&1 || cleanup_and_fail "$tmpdir"

  security import "$p12_path" \
    -k "$LOGIN_KEYCHAIN" \
    -P "" \
    -T /usr/bin/codesign >/dev/null 2>&1 || cleanup_and_fail "$tmpdir"

  if ! security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$LOGIN_KEYCHAIN" \
    "$cert_path" >/dev/null 2>&1; then
    echo "  WARN: Could not mark the local signing certificate trusted; trying it anyway."
  fi

  rm -rf "$tmpdir"
}

resolve_signing_identity() {
  local identity
  identity="$(find_local_signing_identity)"
  if [[ -n "$identity" ]]; then
    SIGNING_IDENTITY="$identity"
    echo "  Using existing local signing identity: ${SIGNING_IDENTITY_NAME}"
    return
  fi

  echo "  Creating local signing identity: ${SIGNING_IDENTITY_NAME}"
  create_local_signing_identity || true

  identity="$(find_local_signing_identity)"
  if [[ -n "$identity" ]]; then
    SIGNING_IDENTITY="$identity"
    echo "  Created local signing identity: ${SIGNING_IDENTITY_NAME}"
    return
  fi

  SIGNING_IDENTITY="-"
  echo "  WARN: Could not create a stable local signing identity."
  echo "  WARN: This install will be ad-hoc signed and may need Accessibility approval again."
}

sign_installed_app_with_identity() {
  local identity="$1"
  local codesign_args=(--force --sign "$identity" --timestamp=none)

  if [[ -d /Applications/Ice.app/Contents/Frameworks/Sparkle.framework ]]; then
    codesign --force --sign "$identity" --timestamp=none \
      /Applications/Ice.app/Contents/Frameworks/Sparkle.framework 2>/dev/null || return 1
  fi

  codesign "${codesign_args[@]}" /Applications/Ice.app 2>/dev/null
}

codesign_installed_app() {
  if sign_installed_app_with_identity "$SIGNING_IDENTITY"; then
    return
  fi

  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    return 1
  fi

  echo "  WARN: Stable local signing failed; falling back to ad-hoc signing."
  echo "  WARN: Accessibility may need approval again."
  SIGNING_IDENTITY="-"
  sign_installed_app_with_identity "$SIGNING_IDENTITY"
}

require_xcodebuild() {
  if xcodebuild -version >/dev/null 2>&1; then
    return
  fi

  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  echo "  ERROR: Ice requires full Xcode to build."
  echo "  Current developer directory: ${developer_dir:-not set}"
  echo "  Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
}

echo "=== Building Ice ==="
require_xcodebuild
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
  DEBUG_INFORMATION_FORMAT=dwarf \
  build 2>&1 | tail -3

echo "=== Preparing signing identity ==="
resolve_signing_identity

echo "=== Stopping Ice ==="
pkill -x Ice 2>/dev/null || true
sleep 1

echo "=== Installing ==="
rm -rf /Applications/Ice.app
cp -R build/Build/Products/Release/Ice.app /Applications/Ice.app
codesign_installed_app

echo "=== Launching ==="
open /Applications/Ice.app

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "=== Done! Existing permissions were left in place, but this app is ad-hoc signed ==="
else
  echo "=== Done! Existing permissions were left in place ==="
  echo "If this is the first stable local-signed install, approve Ice once in Accessibility."
fi
