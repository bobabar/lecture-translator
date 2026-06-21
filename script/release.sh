#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-Lecture Translator}"
EXECUTABLE_NAME="LectureTranslatorNative"
BUNDLE_ID="${BUNDLE_ID:-com.brownsugar.lecturetranslator}"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-14.0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
RESOURCE_SOURCE="$ROOT_DIR/resources"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_PATH="$RESOURCE_SOURCE/AppIcon.icns"
PRIVACY_MANIFEST="$RESOURCE_SOURCE/PrivacyInfo.xcprivacy"
ENTITLEMENTS="$RESOURCE_SOURCE/Release.entitlements"
WHISPER_ENTITLEMENTS="$RESOURCE_SOURCE/WhisperHelper.entitlements"
ARCH="$(uname -m)"
ARTIFACT_BASENAME="LectureTranslator-$APP_VERSION-macOS-$ARCH"
ZIP_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.zip"
DMG_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.dmg"
CHECKSUM_PATH="$RELEASE_DIR/SHA256SUMS.txt"
MANIFEST_PATH="$RELEASE_DIR/release-manifest.json"
DMG_ROOT="$RELEASE_DIR/dmg-root"

if [[ -z "${CLANG_MODULE_CACHE_PATH:-}" ]]; then
  export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
fi

if [[ -z "${TMPDIR:-}" ]]; then
  export TMPDIR="$ROOT_DIR/.build/tmp"
fi

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$TMPDIR"

swift_build() {
  if [[ -n "${SWIFT_BUILD_EXTRA_ARGS:-}" ]]; then
    # Intentionally split extra SwiftPM flags supplied by release automation.
    set -- $SWIFT_BUILD_EXTRA_ARGS "$@"
  fi

  if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    set -- --disable-sandbox "$@"
  fi

  swift build "$@" --package-path "$ROOT_DIR" -c release
}

required_resource() {
  if [[ ! -e "$RESOURCE_SOURCE/$1" ]]; then
    echo "error: missing required release resource: resources/$1" >&2
    echo "hint: run ./script/prepare_whisper_resources.sh before packaging a release." >&2
    exit 1
  fi
}

detect_identity() {
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "$SIGN_IDENTITY"
    return
  fi

  local developer_id
  developer_id="$(security find-identity -p codesigning -v 2>/dev/null | awk -F '"' '/Developer ID Application/ {print $2; exit}')"
  if [[ -n "$developer_id" ]]; then
    echo "$developer_id"
  else
    echo "-"
  fi
}

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.education</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Lecture Translator needs microphone access to translate live speech locally with Whisper.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Brownsugar. All rights reserved.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

sign_path() {
  local path="$1"
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --options runtime "$path"
  else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$path"
  fi
}

local_dependency_path() {
  local code_path="$1"
  local dependency_name="$2"

  case "$code_path" in
    "$APP_RESOURCES/bin/"*)
      echo "@executable_path/../lib/$dependency_name"
      ;;
    "$APP_RESOURCES/lib/"*)
      echo "@loader_path/$dependency_name"
      ;;
    "$APP_RESOURCES/libexec/"*)
      echo "@loader_path/../lib/$dependency_name"
      ;;
    "$APP_MACOS/"*)
      echo "@executable_path/../Resources/lib/$dependency_name"
      ;;
    *)
      echo "@rpath/$dependency_name"
      ;;
  esac
}

relink_code_path() {
  local code_path="$1"

  if [[ "$code_path" == "$APP_RESOURCES/lib/"*.dylib ]]; then
    install_name_tool -id "@loader_path/$(basename "$code_path")" "$code_path" 2>/dev/null || true
  fi

  while IFS= read -r dependency; do
    local dependency_name replacement
    dependency_name="$(basename "$dependency")"
    if [[ -z "$dependency_name" || ! -f "$APP_RESOURCES/lib/$dependency_name" ]]; then
      continue
    fi

    case "$dependency" in
      @rpath/*|/opt/homebrew/opt/*/lib/*|/usr/local/opt/*/lib/*|/opt/homebrew/Cellar/*/lib/*|/usr/local/Cellar/*/lib/*)
        replacement="$(local_dependency_path "$code_path" "$dependency_name")"
        install_name_tool -change "$dependency" "$replacement" "$code_path" 2>/dev/null || true
        ;;
    esac
  done < <(otool -L "$code_path" 2>/dev/null | awk 'NR > 1 {print $1}')
}

relink_bundled_runtime() {
  relink_code_path "$APP_RESOURCES/bin/whisper-cli"

  while IFS= read -r -d '' code_path; do
    relink_code_path "$code_path"
  done < <(find "$APP_RESOURCES" -type f \( -name "*.dylib" -o -name "*.so" \) -print0)
}

sign_app() {
  while IFS= read -r -d '' code_path; do
    sign_path "$code_path"
  done < <(find "$APP_RESOURCES" -type f \( -name "*.dylib" -o -name "*.so" \) -print0)

  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --options runtime --entitlements "$WHISPER_ENTITLEMENTS" "$APP_RESOURCES/bin/whisper-cli"
  else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$WHISPER_ENTITLEMENTS" "$APP_RESOURCES/bin/whisper-cli"
  fi

  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
  else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
  fi
}

create_dmg() {
  rm -rf "$DMG_ROOT"
  mkdir -p "$DMG_ROOT"
  /usr/bin/ditto --noextattr --norsrc "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
  ln -s /Applications "$DMG_ROOT/Applications"
  rm -f "$DMG_PATH"
  if ! hdiutil create -volname "$APP_NAME $APP_VERSION" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH" >/dev/null; then
    echo "warning: hdiutil create failed; falling back to hdiutil makehybrid." >&2
    rm -f "$DMG_PATH"
    hdiutil makehybrid -hfs -hfs-volume-name "$APP_NAME $APP_VERSION" -o "$DMG_PATH" "$DMG_ROOT" >/dev/null
  fi

  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
  fi
  rm -rf "$DMG_ROOT"
}

write_manifest() {
  local created_at signing_label notarization_ready
  created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  signing_label="$SIGNING_IDENTITY"
  notarization_ready=false
  if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    notarization_ready=true
  else
    signing_label="ad-hoc"
  fi

  cat >"$MANIFEST_PATH" <<JSON
{
  "appName": "$APP_NAME",
  "bundleIdentifier": "$BUNDLE_ID",
  "version": "$APP_VERSION",
  "build": "$BUILD_NUMBER",
  "architecture": "$ARCH",
  "createdAt": "$created_at",
  "signingIdentity": "$signing_label",
  "hardenedRuntime": true,
  "notarizationReady": $notarization_ready,
  "artifacts": {
    "app": "$APP_BUNDLE",
    "zip": "$ZIP_PATH",
    "dmg": "$DMG_PATH",
    "checksums": "$CHECKSUM_PATH"
  }
}
JSON
}

required_resource "bin/whisper-cli"
required_resource "models/ggml-small.bin"
required_resource "models/ggml-base.bin"
required_resource "lib/libwhisper.1.dylib"
required_resource "lib/libggml.0.dylib"
required_resource "libexec/libggml-cpu-apple_m1.so"
required_resource "licenses/WHISPER_CPP_LICENSE"
required_resource "licenses/GGML_LICENSE"
required_resource "Release.entitlements"
required_resource "WhisperHelper.entitlements"
required_resource "PrivacyInfo.xcprivacy"

if [[ ! -f "$ICON_PATH" ]]; then
  swift "$ROOT_DIR/script/make_app_icon.swift" "$ICON_PATH"
fi

swift_build
BUILD_BINARY="$(swift_build --show-bin-path)/$EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

rsync -a --delete "$RESOURCE_SOURCE/bin" "$APP_RESOURCES/"
rsync -a --delete "$RESOURCE_SOURCE/lib" "$APP_RESOURCES/"
rsync -a --delete "$RESOURCE_SOURCE/libexec" "$APP_RESOURCES/"
rsync -a --delete "$RESOURCE_SOURCE/models" "$APP_RESOURCES/"
rsync -a --delete "$RESOURCE_SOURCE/licenses" "$APP_RESOURCES/"
cp "$ICON_PATH" "$APP_RESOURCES/AppIcon.icns"
cp "$PRIVACY_MANIFEST" "$APP_RESOURCES/PrivacyInfo.xcprivacy"
write_info_plist
relink_bundled_runtime

/usr/bin/xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true

SIGNING_IDENTITY="$(detect_identity)"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "warning: no Developer ID Application identity found; using ad-hoc hardened runtime signing." >&2
fi

sign_app
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
create_dmg

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" > "$CHECKSUM_PATH"
)
write_manifest

echo "Release artifacts:"
echo "  $APP_BUNDLE"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
echo "  $MANIFEST_PATH"
