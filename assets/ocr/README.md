Desktop OCR runtime/model assets (and optional Whisper runtime payload) are prepared into:

- `assets/ocr/desktop_runtime/`

The folder is generated from GitHub Release runtime assets by:

- `dart run tools/prepare_desktop_runtime.dart`

Do not commit `assets/ocr/desktop_runtime/` into git. The folder is ignored by
`.gitignore` and should be generated locally/CI before desktop run/build.
