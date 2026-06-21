#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_PATH="${1:-$RELEASE_DIR/Lecture Translator.app}"
ZIP_PATH="${2:-$(find "$RELEASE_DIR" -maxdepth 1 -name "LectureTranslator-*.zip" -print | sort | tail -n 1)}"
TMP_DIR="${TMPDIR:-/tmp}/lecture-translator-release-check"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
/usr/bin/ditto -x -k "$ZIP_PATH" "$TMP_DIR"
codesign --verify --deep --strict --verbose=2 "$TMP_DIR/Lecture Translator.app"

SAMPLE="/opt/homebrew/opt/whisper-cpp/share/whisper-cpp/jfk.wav"
if [[ -f "$SAMPLE" ]]; then
  CPU_BRAND="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
  case "$CPU_BRAND" in
    *M4*) BACKEND="$APP_PATH/Contents/Resources/libexec/libggml-cpu-apple_m4.so" ;;
    *M2*|*M3*) BACKEND="$APP_PATH/Contents/Resources/libexec/libggml-cpu-apple_m2_m3.so" ;;
    *) BACKEND="$APP_PATH/Contents/Resources/libexec/libggml-cpu-apple_m1.so" ;;
  esac
  [[ -f "$BACKEND" ]] || BACKEND="$(find "$APP_PATH/Contents/Resources/libexec" -name "libggml-cpu-apple_*.so" -print | sort | tail -n 1)"
  if GGML_BACKEND_PATH="$BACKEND" \
      "$APP_PATH/Contents/Resources/bin/whisper-cli" \
      -m "$APP_PATH/Contents/Resources/models/ggml-base.bin" \
      -f "$SAMPLE" \
      -l en \
      -t 4 \
      -nt \
      -np \
      --no-fallback >/dev/null 2>&1; then
    echo "Bundled Whisper smoke test passed."
  else
    echo "Bundled Whisper smoke test failed." >&2
    exit 1
  fi
fi

if spctl -a -vv "$APP_PATH"; then
  echo "Gatekeeper assessment accepted."
else
  echo "Gatekeeper assessment rejected. This is expected for ad-hoc builds; use Developer ID signing and notarization for public distribution."
fi

echo "Release verification completed for $APP_PATH"
