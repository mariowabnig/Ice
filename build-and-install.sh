#!/bin/bash
set -euo pipefail

SIGNING_IDENTITY_NAME="Ice Local Development"
SIGNING_IDENTITY="-"
INSTALL_APP_PATH=""
ARTIFACT_TMPDIR=""
LOGIN_KEYCHAIN="$(
  security default-keychain -d user 2>/dev/null |
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' || true
)"
LOGIN_KEYCHAIN="${LOGIN_KEYCHAIN:-${HOME}/Library/Keychains/login.keychain-db}"

cleanup_artifact_tmpdir() {
  if [[ -n "$ARTIFACT_TMPDIR" && -d "$ARTIFACT_TMPDIR" ]]; then
    rm -rf "$ARTIFACT_TMPDIR"
  fi
}

trap cleanup_artifact_tmpdir EXIT

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
  local p12_password="ice-local-development"

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
    -passout pass:"$p12_password" >/dev/null 2>&1 || cleanup_and_fail "$tmpdir"

  security import "$p12_path" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$p12_password" \
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

xcodebuild_available() {
  xcodebuild -version >/dev/null 2>&1
}

build_local_app() {
  echo "=== Building Ice ==="
  xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
    DEBUG_INFORMATION_FORMAT=dwarf \
    build 2>&1 | tail -3
  INSTALL_APP_PATH="build/Build/Products/Release/Ice.app"
}

download_artifact_app() {
  local repo="${ICE_ARTIFACT_REPO:-mariowabnig/Ice}"
  local workflow="${ICE_ARTIFACT_WORKFLOW:-build-artifact.yml}"
  local branch="${ICE_ARTIFACT_BRANCH:-main}"
  local artifact_name="${ICE_ARTIFACT_NAME:-Ice-app}"
  local run_id="${ICE_ARTIFACT_RUN_ID:-}"

  echo "=== Fetching Ice artifact ==="
  if ! command -v gh >/dev/null 2>&1; then
    echo "  ERROR: Full Xcode is unavailable and GitHub CLI (gh) is not installed."
    echo "  Install Xcode for local builds, or install/authenticate gh for artifact installs."
    exit 1
  fi

  if [[ -z "$run_id" ]]; then
    run_id="$(
      gh run list \
        --repo "$repo" \
        --workflow "$workflow" \
        --branch "$branch" \
        --status success \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId'
    )"
  fi

  if [[ -z "$run_id" || "$run_id" == "null" ]]; then
    echo "  ERROR: No successful ${workflow} run found on ${repo}/${branch}."
    echo "  Trigger the workflow once, or set ICE_ARTIFACT_RUN_ID to a known good run."
    exit 1
  fi

  ARTIFACT_TMPDIR="$(mktemp -d)"
  local download_dir="$ARTIFACT_TMPDIR/download"
  local app_dir="$ARTIFACT_TMPDIR/app"
  mkdir -p "$download_dir" "$app_dir"

  gh run download "$run_id" \
    --repo "$repo" \
    --name "$artifact_name" \
    --dir "$download_dir"

  local zip_path="$download_dir/Ice.app.zip"
  if [[ ! -f "$zip_path" ]]; then
    zip_path="$(find "$download_dir" -name "*.zip" -print | head -n 1)"
  fi
  if [[ -z "$zip_path" || ! -f "$zip_path" ]]; then
    echo "  ERROR: Downloaded artifact did not contain Ice.app.zip."
    exit 1
  fi

  ditto -x -k "$zip_path" "$app_dir"
  if [[ ! -d "$app_dir/Ice.app" ]]; then
    echo "  ERROR: Downloaded artifact did not unpack to Ice.app."
    exit 1
  fi

  INSTALL_APP_PATH="$app_dir/Ice.app"
  echo "  Using artifact ${artifact_name} from run ${run_id}."
}

prepare_install_source() {
  if xcodebuild_available; then
    build_local_app
    return
  fi

  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"
  echo "  Full Xcode is not available locally."
  echo "  Current developer directory: ${developer_dir:-not set}"
  echo "  Falling back to the latest GitHub Actions app artifact."
  download_artifact_app
}

prepare_install_source

echo "=== Preparing signing identity ==="
resolve_signing_identity

echo "=== Stopping Ice ==="
pkill -x Ice 2>/dev/null || true
sleep 1

echo "=== Installing ==="
rm -rf /Applications/Ice.app
cp -R "$INSTALL_APP_PATH" /Applications/Ice.app
codesign_installed_app

echo "=== Launching ==="
open /Applications/Ice.app

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "=== Done! Existing permissions were left in place, but this app is ad-hoc signed ==="
else
  echo "=== Done! Existing permissions were left in place ==="
  echo "If this is the first stable local-signed install, approve Ice once in Accessibility."
fi
