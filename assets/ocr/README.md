Bundled OCR runtime/model assets live under:

- `assets/ocr/linux/python/` for Python runtime packages (for example: prebuilt
  site-packages containing `rapidocr_onnxruntime` and `pypdfium2`)
- `assets/ocr/linux/models/` for OCR model files used by the Linux fallback

The Linux OCR bridge extracts these assets at runtime when present and prefers
them over system-level Python paths. The app does not perform runtime `pip
install`.
