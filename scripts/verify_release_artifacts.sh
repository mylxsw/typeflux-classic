#!/usr/bin/env bash
set -euo pipefail
exec 2>&1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Typeflux}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/.build/release}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/app/Info.plist")"
PACKAGE_PREFIX="${TYPEFLUX_PACKAGE_PREFIX:-Typeflux-Classic-$VERSION}"

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "Error: release build directory does not exist: ${BUILD_DIR}" >&2
  echo "Error: build the release artifacts before running this verifier." >&2
  exit 1
fi

echo "Release artifacts in ${BUILD_DIR}:"
find "$BUILD_DIR" -maxdepth 1 \( -name "Typeflux*.dmg" -o -name "Typeflux*.zip" \) -print | sort

missing_artifacts=()
require_artifact() {
  local artifact_path="$1"

  if [[ -f "$artifact_path" ]]; then
    echo "Found artifact: ${artifact_path}"
  else
    missing_artifacts+=("$artifact_path")
  fi
}

for arch in apple-silicon intel; do
  require_artifact "$BUILD_DIR/$PACKAGE_PREFIX-$arch.dmg"
  require_artifact "$BUILD_DIR/$PACKAGE_PREFIX-$arch.zip"
done

if (( ${#missing_artifacts[@]} > 0 )); then
  echo "Error: missing expected release artifacts:" >&2
  printf '  %s\n' "${missing_artifacts[@]}" >&2
  exit 1
fi

VERIFY_ROOT="$(mktemp -d)"
trap 'rm -rf "$VERIFY_ROOT"' EXIT

for arch in apple-silicon intel; do
  if [[ "$arch" == "apple-silicon" ]]; then
    expected_macho_arch="arm64"
  else
    expected_macho_arch="x86_64"
  fi

  app_verify_dir="$VERIFY_ROOT/$arch"
  mkdir -p "$app_verify_dir"
  echo "Verifying $PACKAGE_PREFIX-$arch..."
  ditto -x -k "$BUILD_DIR/$PACKAGE_PREFIX-$arch.zip" "$app_verify_dir"
  echo "Verifying code signature for $arch ZIP app..."
  codesign --verify --deep --strict --verbose=2 "$app_verify_dir/$APP_NAME.app"
  echo "Assessing Gatekeeper acceptance for $arch ZIP app..."
  spctl --assess --type execute --verbose=4 "$app_verify_dir/$APP_NAME.app"
  echo "Auditing Mach-O metadata for $arch ZIP app..."
  "$ROOT_DIR/scripts/audit_macho_minos.sh" "$app_verify_dir/$APP_NAME.app" "${TYPEFLUX_MAX_MACHO_MINOS:-13.4}" "$expected_macho_arch"
  echo "Validating stapled ticket for $arch DMG..."
  xcrun stapler validate "$BUILD_DIR/$PACKAGE_PREFIX-$arch.dmg"
done
