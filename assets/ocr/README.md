Legacy OCR runtime/model payloads used to be prepared into:

- `assets/ocr/desktop_runtime/`

The runtime-first product no longer bundles or prepares these local payloads for
normal App run/build/release paths. The old helper scripts and workflow payload
release jobs have been removed.

## Runtime Strategy

The main client does not build or link a local transcription runtime. Desktop
run/build/release paths do not download OCR or Whisper assets. Managed-pro
transcription and media understanding run through cloud runtime HTTP services.
