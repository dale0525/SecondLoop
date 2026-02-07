import 'attachment_ocr_text_normalizer.dart';

enum AttachmentTextSource {
  none,
  extracted,
  readable,
  ocr,
}

final class AttachmentTextSelection {
  const AttachmentTextSelection({
    required this.source,
    required this.excerpt,
    required this.full,
  });

  final AttachmentTextSource source;
  final String excerpt;
  final String full;

  bool get hasAnyText => excerpt.isNotEmpty || full.isNotEmpty;
}

final class _TextSource {
  const _TextSource({
    required this.excerpt,
    required this.full,
  });

  final String excerpt;
  final String full;

  bool get hasAnyText => excerpt.isNotEmpty || full.isNotEmpty;
}

AttachmentTextSelection selectAttachmentDisplayText(
  Map<String, Object?>? payload,
) {
  if (payload == null) {
    return const AttachmentTextSelection(
      source: AttachmentTextSource.none,
      excerpt: '',
      full: '',
    );
  }

  String read(String key, {bool normalizeOcr = false}) {
    final raw = (payload[key] ?? '').toString();
    final normalized = normalizeOcr ? normalizeOcrTextForDisplay(raw) : raw;
    return normalized.trim();
  }

  final extracted = _TextSource(
    excerpt: read('extracted_text_excerpt'),
    full: read('extracted_text_full'),
  );
  final readable = _TextSource(
    excerpt: read('readable_text_excerpt'),
    full: read('readable_text_full'),
  );
  final ocr = _TextSource(
    excerpt: read('ocr_text_excerpt', normalizeOcr: true),
    full: read('ocr_text_full', normalizeOcr: true),
  );

  final extractedProbe =
      extracted.excerpt.isNotEmpty ? extracted.excerpt : extracted.full;
  final ocrProbe = ocr.excerpt.isNotEmpty ? ocr.excerpt : ocr.full;
  final extractedDegraded =
      extracted.hasAnyText && extractedTextLooksDegraded(extractedProbe);
  final ocrDegraded = ocr.hasAnyText && extractedTextLooksDegraded(ocrProbe);
  final preferOcrOverExtracted = ocr.hasAnyText &&
      extracted.hasAnyText &&
      extractedDegraded &&
      !ocrDegraded;

  final candidates = <(AttachmentTextSource, _TextSource)>[
    if (preferOcrOverExtracted)
      (AttachmentTextSource.ocr, ocr)
    else
      (AttachmentTextSource.extracted, extracted),
    (AttachmentTextSource.readable, readable),
    if (preferOcrOverExtracted)
      (AttachmentTextSource.extracted, extracted)
    else
      (AttachmentTextSource.ocr, ocr),
  ];

  for (final candidate in candidates) {
    final source = candidate.$2;
    if (!source.hasAnyText) continue;
    return AttachmentTextSelection(
      source: candidate.$1,
      excerpt: source.excerpt,
      full: source.full,
    );
  }

  return const AttachmentTextSelection(
    source: AttachmentTextSource.none,
    excerpt: '',
    full: '',
  );
}

bool extractedTextLooksDegraded(String raw) {
  final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.length < 24) return false;
  var meaningfulCount = 0;
  var nonSpaceCount = 0;
  var noisyCount = 0;
  for (final rune in normalized.runes) {
    if (_isWhitespaceRune(rune)) continue;
    nonSpaceCount += 1;
    if (_isMeaningfulRune(rune)) {
      meaningfulCount += 1;
    } else {
      noisyCount += 1;
    }
  }
  if (meaningfulCount == 0) return false;

  final tokens = normalized
      .split(' ')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (tokens.length < 8) return false;

  var considered = 0;
  var singleCharTokens = 0;
  var totalTokenLen = 0;
  for (final token in tokens) {
    final meaningfulLen = token.runes.where(_isMeaningfulRune).length;
    if (meaningfulLen <= 0) continue;
    considered += 1;
    totalTokenLen += meaningfulLen;
    if (meaningfulLen == 1) {
      singleCharTokens += 1;
    }
  }
  if (considered < 8) return false;

  final singleCharRatio = singleCharTokens / considered;
  final avgTokenLen = totalTokenLen / considered;
  final noisyRatio =
      nonSpaceCount <= 0 ? 0.0 : noisyCount / nonSpaceCount.toDouble();

  if (singleCharRatio >= 0.5) return true;
  if (avgTokenLen < 1.8) return true;
  if (meaningfulCount >= 20 && noisyRatio > 0.45) return true;
  if (considered >= 12 && singleCharRatio >= 0.4 && noisyRatio > 0.2) {
    return true;
  }

  final lines = raw
      .split(RegExp(r'\r?\n'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (lines.length >= 8) {
    var lineCount = 0;
    var shortLineCount = 0;
    var totalLineLen = 0;
    for (final line in lines) {
      final meaningfulLen = line.runes.where(_isMeaningfulRune).length;
      if (meaningfulLen <= 0) continue;
      lineCount += 1;
      totalLineLen += meaningfulLen;
      if (meaningfulLen <= 3) {
        shortLineCount += 1;
      }
    }
    if (lineCount >= 8) {
      final avgLineLen = totalLineLen / lineCount;
      final shortLineRatio = shortLineCount / lineCount;
      if (avgLineLen < 3.0) return true;
      if (avgLineLen < 4.0 && shortLineRatio >= 0.45) return true;
    }
  }
  return false;
}

bool _isWhitespaceRune(int rune) => String.fromCharCode(rune).trim().isEmpty;

bool _isMeaningfulRune(int rune) {
  if (_isAsciiAlphaNumRune(rune)) return true;
  if (_isCjkOrKanaOrHangulRune(rune)) return true;
  if (rune > 127 && !_isCommonPunctuationRune(rune)) return true;
  return false;
}

bool _isAsciiAlphaNumRune(int rune) {
  return (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A);
}

bool _isCjkOrKanaOrHangulRune(int rune) {
  return (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0x31F0 && rune <= 0x31FF) ||
      (rune >= 0x1100 && rune <= 0x11FF) ||
      (rune >= 0x3130 && rune <= 0x318F) ||
      (rune >= 0xAC00 && rune <= 0xD7AF);
}

bool _isCommonPunctuationRune(int rune) =>
    _commonPunctuationRunes.contains(rune);

final Set<int> _commonPunctuationRunes =
    '.,;:!?()[]{}<>/\\|@#%^&*_+=~`"\'-，。；：！？（）【】《》“”‘’、…·￥'.runes.toSet();
