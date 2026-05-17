Desktop OCR runtime/model assets (and optional Whisper runtime payload) are prepared into:

- `assets/ocr/desktop_runtime/`

The folder is generated from GitHub Release runtime assets by:

- `dart run tools/prepare_desktop_runtime.dart`

Do not commit `assets/ocr/desktop_runtime/` into git. The folder is ignored by
`.gitignore` and should be generated locally/CI before desktop run/build.

## Runtime Strategy

The main client does not build or link a local transcription runtime. Desktop
runtime payloads are downloaded release artifacts, while managed-pro
transcription and media understanding run through cloud runtime HTTP services.

Packaging checks should validate that release payloads can be prepared and
mirrored into the app support directory. They should not require a local native
toolchain in the normal App build path.
