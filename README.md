# Lecture Translator

Lecture Translator is a local macOS 15+ app for live lecture translation. It captures microphone audio, runs Whisper locally for source transcription, uses Apple Translation for English captions, and saves lecture output for review.

The app is designed for classrooms and lectures where students need low-friction live captions, pause/resume support during breaks, autosaved notes, and exportable transcripts.

## Install From Source

Lecture Translator is distributed as source code. Clone the repository, prepare the local Whisper runtime, then build and run the macOS app on your machine.

Requires macOS 15 or newer. Apple Translation may prompt macOS to prepare or download language support for the selected source language.

Install build prerequisites:

```sh
brew install whisper-cpp ggml libomp
```

Clone and enter the repository:

```sh
git clone https://github.com/bobabar/lecture-translator.git
cd lecture-translator
```

Prepare local Whisper runtime assets and models:

```sh
./script/prepare_whisper_resources.sh
```

Build and run the app:

```sh
./script/build_and_run.sh
```

This local build flow creates the app on your own Mac. macOS may still request microphone permission the first time the app starts.

## Features

- Local Whisper transcription and English translation
- Apple Translation text translation instead of Whisper direct audio translation
- Multilingual source-language selection
- Whisper model picker with `large-v3-turbo` recommended for 16 GB Macs and `small` for lower latency
- Pause/resume for lecture breaks
- Autosave, manual save, and export to Markdown or plain text
- Source-first macOS build flow
- No OpenAI key, token billing, server, Electron, or Node.js runtime

## Lecture Accuracy

Select the spoken lecture language before starting. The app intentionally does not expose Whisper auto-detect because fixed-language transcription gives more reliable source transcripts and translations in a classroom.

For Mandarin lectures, leave Source set to `Chinese (Mandarin)` and use the `Lecture` or `High Accuracy` profile. Use `Large v3 Turbo` on 16 GB Macs; switch to `Small` if you need lower latency.

## Development

Build the Swift package:

```sh
swift build
```

Run a local app bundle:

```sh
./script/build_and_run.sh
```

The repository intentionally does not commit generated app bundles, Whisper model binaries, `whisper-cli`, or runtime dylibs. Those assets are large and should be generated locally with:

```sh
./script/prepare_whisper_resources.sh
```

If you already have a prepared `resources` directory, copy it in with:

```sh
WHISPER_RESOURCE_SOURCE=/path/to/resources ./script/prepare_whisper_resources.sh
```

## Bundled Runtime

Local app bundles are self-contained after `script/prepare_whisper_resources.sh` has populated `resources/bin`, `resources/lib`, `resources/libexec`, and `resources/models`.

Default models:

- `ggml-base.bin`
- `ggml-small.bin`
- `ggml-large-v3-turbo.bin`

Additional Whisper `.bin` models can be added to `resources/models` before building a local app bundle. Models are downloaded from the `ggerganov/whisper.cpp` model repository on Hugging Face.

## License

This project is released under the MIT License. Third-party license notices for bundled Whisper/GGML/libomp runtime components live in `resources/licenses`.
