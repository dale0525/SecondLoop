bool hasSufficientOcrTextSignal(
  String text, {
  double minScore = 20,
}) {
  return estimateOcrEffectiveTextScore(text) >= minScore;
}

double estimateOcrEffectiveTextScore(String text) {
  final normalized = _normalizeForScoring(text);
  if (normalized.isEmpty) return 0;

  var score = 0.0;
  for (final rune in normalized.runes) {
    if (_isCjkLikeRune(rune)) {
      score += 1.2;
      continue;
    }

    final ch = String.fromCharCode(rune);
    if (_isAsciiLetterOrDigit(ch) || _isUnicodeLetterOrDigit(ch)) {
      score += 1.0;
    }
  }

  if (_looksTokenizedAsciiNoise(normalized)) {
    score *= 0.55;
  }

  return score;
}

bool shouldPreferExtractedTextOverOcr({
  required String extractedText,
  required String ocrText,
  double minScoreDelta = 12,
}) {
  final extractedScore = estimateOcrEffectiveTextScore(extractedText);
  final ocrScore = estimateOcrEffectiveTextScore(ocrText);

  if (extractedScore <= 0) return false;
  if (ocrScore <= 0) return true;

  if (_looksTokenizedAsciiNoise(ocrText) &&
      extractedScore >= (ocrScore * 0.8)) {
    return true;
  }

  return extractedScore >= (ocrScore + minScoreDelta);
}

String _normalizeForScoring(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _looksTokenizedAsciiNoise(String raw) {
  final normalized = _normalizeForScoring(raw);
  if (normalized.length < 24) return false;

  final tokens = normalized.split(' ').where((v) => v.isNotEmpty).toList();
  if (tokens.length < 8) return false;

  var asciiSingleChar = 0;
  var asciiTokens = 0;
  for (final token in tokens) {
    final stripped = token.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (stripped.isEmpty) continue;
    asciiTokens += 1;
    if (stripped.length == 1) asciiSingleChar += 1;
  }

  if (asciiTokens < 8) return false;
  final ratio = asciiSingleChar / asciiTokens;
  return ratio >= 0.45;
}

bool _isAsciiLetterOrDigit(String ch) {
  final code = ch.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A);
}

bool _isUnicodeLetterOrDigit(String ch) {
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);
}

bool _isCjkLikeRune(int rune) {
  return (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0xAC00 && rune <= 0xD7AF);
}
