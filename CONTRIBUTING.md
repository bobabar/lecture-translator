# Contributing

Thanks for helping improve Lecture Translator.

## Local Setup

```sh
brew install whisper-cpp libomp
./script/prepare_whisper_resources.sh
swift build
```

Use `./script/build_and_run.sh` for local app testing and `./script/release.sh` for release packaging checks.

## Pull Requests

- Keep changes focused and explain the user impact.
- Do not commit `dist`, `.build`, Whisper model binaries, `whisper-cli`, dylibs, or generated release archives.
- Run `swift build` before opening a PR.
- For release-script changes, run `bash -n script/*.sh` and, when resources are available, `./script/verify_release.sh`.

## Product Direction

Lecture Translator should stay local-first, classroom-focused, and understandable to non-technical students. Features that require remote services should be optional and clearly labeled.
