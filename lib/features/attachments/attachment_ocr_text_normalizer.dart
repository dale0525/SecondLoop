final RegExp _ocrPageHeaderPattern =
    RegExp(r'^\s*\[page\s+\d+\]\s*\n?', multiLine: true, caseSensitive: false);

String normalizeOcrTextForDisplay(String raw) {
  return raw
      .replaceAll(_ocrPageHeaderPattern, '')
      .replaceAll('\r\n', '\n')
      .trim();
}
