#!/usr/bin/env bash
#
# Amber Podcast — local macOS build.
# Replaces the GitHub Actions workflow while CI is disabled (billing).
#
# Usage:
#   ./scripts/build-local.sh                 # unsigned .ipa in dist/
#   ./scripts/build-local.sh --sign          # also zsign with the local cert
#   ./scripts/build-local.sh --sign --publish
#
# Signing env (required for --sign):
#   AMBER_CERT      path to .p12
#   AMBER_CERT_PASS path to a file containing the p12 password (or literal password)
#   AMBER_PROVISION path to .mobileprovision
#   AMBER_BUNDLE_ID target bundle id, e.g. com.ioslgm.46542
#
# Requires: Xcode 26 (iOS 26 SDK), xcodegen, python3, zip, zsign (for --sign).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT/ios"
DIST_DIR="$ROOT/dist"
ARCHIVE="$IOS_DIR/build/AmberPodcast.xcarchive"
IPA="$DIST_DIR/AmberPodcast.ipa"

SIGN=0
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --sign) SIGN=1 ;;
    --publish) PUBLISH=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need xcodebuild
need xcodegen
need python3
need zip

echo "==> Xcode"; xcodebuild -version

echo "==> Generate project"
cd "$IOS_DIR"
xcodegen generate

echo "==> Archive (unsigned)"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project AmberPodcast.xcodeproj \
  -scheme AmberPodcast \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  COMPILER_INDEX_STORE_ENABLE=NO

echo "==> Package IPA"
rm -rf "$IOS_DIR/build/Payload" "$IPA"
mkdir -p "$IOS_DIR/build/Payload" "$DIST_DIR"
cp -r "$ARCHIVE/Products/Applications/"*.app "$IOS_DIR/build/Payload/"

python3 - "$IOS_DIR/build/Payload" <<'PY'
import glob, os, plistlib, sys

payload = sys.argv[1]
for path in glob.glob(os.path.join(payload, "*.app", "Info.plist")):
    with open(path, "rb") as fh:
        info = plistlib.load(fh)
    info["UILaunchScreen"] = {}
    info["UIBackgroundModes"] = ["audio", "processing"]
    info["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait"]
    with open(path, "wb") as fh:
        plistlib.dump(info, fh)
    print(f"    {os.path.basename(info.get('CFBundleDisplayName', 'App'))}: "
          f"{info.get('CFBundleShortVersionString')} (build {info.get('CFBundleVersion')})")
PY

cd "$IOS_DIR/build"
zip -qry "$IPA" Payload
echo "==> $IPA"
ls -lh "$IPA"

if [[ $SIGN -eq 1 ]]; then
  need zsign
  : "${AMBER_CERT:?set AMBER_CERT}"
  : "${AMBER_PROVISION:?set AMBER_PROVISION}"
  : "${AMBER_BUNDLE_ID:?set AMBER_BUNDLE_ID}"
  if [[ -f "${AMBER_CERT_PASS:-}" ]]; then
    PASS="$(cat "$AMBER_CERT_PASS")"
  else
    PASS="${AMBER_CERT_PASS:?set AMBER_CERT_PASS (file path or literal)}"
  fi
  SIGNED="$DIST_DIR/AmberPodcast-signed.ipa"
  echo "==> Sign with zsign"
  zsign -k "$AMBER_CERT" -p "$PASS" -m "$AMBER_PROVISION" \
        -b "$AMBER_BUNDLE_ID" -n "Amber 播客" -P -z 1 \
        -o "$SIGNED" "$IPA"
  echo "==> $SIGNED"
  ls -lh "$SIGNED"
  IPA="$SIGNED"
fi

if [[ $PUBLISH -eq 1 ]]; then
  : "${AMBER_AIRSTORE_DIR:?set AMBER_AIRSTORE_DIR (…/airstore-pro/data/studio/amber-podcast)}"
  cp "$IPA" "$AMBER_AIRSTORE_DIR/amber-podcast_signed.ipa"
  echo "==> Published to $AMBER_AIRSTORE_DIR/amber-podcast_signed.ipa"
  echo "    Now bump projects.json version + changelog on the host, then verify manifest.plist."
fi
