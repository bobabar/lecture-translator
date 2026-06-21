# Third-Party Notices

Lecture Translator can bundle runtime components from:

- `whisper.cpp`
- GGML
- LLVM OpenMP / `libomp`
- Whisper model files distributed through the `ggerganov/whisper.cpp` model repository on Hugging Face

Third-party license text that is included in release bundles lives in `resources/licenses`.

The repository does not commit generated model binaries or runtime dylibs. Use `script/prepare_whisper_resources.sh` to prepare those local assets before building distributable releases.
