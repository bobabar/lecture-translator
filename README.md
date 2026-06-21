# Lecture Translator

Lecture Translator is a local macOS app for live lecture translation. It captures microphone audio, runs Whisper locally, translates multilingual speech into English captions, and saves lecture output for review.

The app is designed for classrooms and lectures where students need low-friction live captions, pause/resume support during breaks, autosaved notes, and exportable transcripts.

## Features

- Local Whisper transcription and English translation
- Multilingual source-language selection
- Whisper model picker with `small` as the recommended lecture model
- Pause/resume for lecture breaks
- Autosave, manual save, and export to Markdown or plain text
- Self-contained release packaging for macOS
- No OpenAI key, token billing, server, Electron, or Node.js runtime

## Release Build

Install build prerequisites:

```sh
brew install whisper-cpp libomp
```

Prepare local Whisper runtime assets:

```sh
./script/prepare_whisper_resources.sh
```

The script copies `whisper-cli`, runtime libraries, and backend libraries from Homebrew, then downloads the default `ggml-base.bin` and `ggml-small.bin` models into `resources/models`.

Build distributable artifacts:

```sh
./script/release.sh
```

The release script builds in Swift release mode, bundles `whisper-cli`, bundled models, runtime libraries, licenses, the app icon, and privacy manifest, then creates:

- `dist/release/Lecture Translator.app`
- `dist/release/LectureTranslator-<version>-macOS-<arch>.zip`
- `dist/release/LectureTranslator-<version>-macOS-<arch>.dmg`
- `dist/release/SHA256SUMS.txt`
- `dist/release/release-manifest.json`

Verify a release:

```sh
./script/verify_release.sh
```

## Development

Build the Swift package:

```sh
swift build
```

Run a local app bundle:

```sh
./script/build_and_run.sh
```

The repository intentionally does not commit generated release artifacts, Whisper model binaries, `whisper-cli`, or runtime dylibs. Those assets are large and should be generated locally with:

```sh
./script/prepare_whisper_resources.sh
```

If you already have a prepared `resources` directory, copy it in with:

```sh
WHISPER_RESOURCE_SOURCE=/path/to/resources ./script/prepare_whisper_resources.sh
```

## Signing And Notarization

For local testing, the release script falls back to ad-hoc hardened-runtime signing when no Developer ID certificate is installed.

For public distribution outside the Mac App Store, install a `Developer ID Application` certificate, then run:

```sh
./script/release.sh
NOTARYTOOL_PROFILE="your-notary-profile" ./script/notarize.sh
```

You can also notarize with `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD` environment variables instead of a notarytool keychain profile.

## Bundled Runtime

Release builds are self-contained after `script/prepare_whisper_resources.sh` has populated `resources/bin`, `resources/lib`, `resources/libexec`, and `resources/models`.

Default models:

- `ggml-small.bin`
- `ggml-base.bin`

Additional Whisper `.bin` models can be added to `resources/models` before running the release script. Models are downloaded from the `ggerganov/whisper.cpp` model repository on Hugging Face.

## License

This project is released under the MIT License. Third-party license notices for bundled Whisper/GGML/libomp runtime components live in `resources/licenses`.
