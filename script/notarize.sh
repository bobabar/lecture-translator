#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
DMG_PATH="${1:-$(find "$RELEASE_DIR" -maxdepth 1 -name "LectureTranslator-*.dmg" -print | sort | tail -n 1)}"

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "usage: $0 path/to/LectureTranslator-version.dmg" >&2
  exit 2
fi

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
else
  : "${APPLE_ID:?Set APPLE_ID or NOTARYTOOL_PROFILE before notarizing.}"
  : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID or NOTARYTOOL_PROFILE before notarizing.}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD or NOTARYTOOL_PROFILE before notarizing.}"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
fi

xcrun stapler staple "$DMG_PATH"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
