# Whisper Models

Whisper model binaries are intentionally not committed to this repository.

Prepare the default local models with:

```sh
./script/prepare_whisper_resources.sh
```

Default release models:

- `ggml-base.bin`
- `ggml-small.bin`
- `ggml-large-v3-turbo.bin`

You can add additional `ggml-*.bin` files here before running `./script/release.sh`.
