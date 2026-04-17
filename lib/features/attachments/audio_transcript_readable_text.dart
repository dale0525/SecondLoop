import '../audio_transcribe/audio_transcribe_turn_view.dart';

import 'audio_transcript_turn_view_display.dart';

String resolveAudioTranscriptReadableFullText(
  Map<String, Object?>? payload, {
  AudioTranscriptTurnView? turnView,
}) {
  final raw =
      _normalizeTranscriptText((payload?['transcript_full'] ?? '').toString());
  if (raw.isEmpty) return '';

  final paragraphPreserving = _normalizeExistingParagraphs(raw);
  if (paragraphPreserving.isNotEmpty) {
    return paragraphPreserving;
  }

  final view = turnView ?? resolveAudioTranscriptTurnView(payload);
  if (view != null &&
      view.status == AudioTranscriptTurnViewStatus.ok &&
      view.turns.length >= 2) {
    final paragraphized = _paragraphizeTranscriptWithTurnHints(
      raw,
      turnCount: view.turns.length,
    );
    if (paragraphized.isNotEmpty) {
      return paragraphized;
    }
  }

  final upgradedSingleNewlines = _upgradeStructuredSingleNewlinesToParagraphs(
    raw,
  );
  if (upgradedSingleNewlines.isNotEmpty) {
    return upgradedSingleNewlines;
  }

  final lineBrokenParagraphized = _paragraphizeLineBrokenTranscript(raw);
  return lineBrokenParagraphized.isNotEmpty ? lineBrokenParagraphized : raw;
}

String _normalizeTranscriptText(String raw) {
  return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
}

String _normalizeExistingParagraphs(String raw) {
  if (!RegExp(r'\n\s*\n').hasMatch(raw)) return '';
  final paragraphs = raw
      .split(RegExp(r'\n\s*\n+'))
      .map(_compactInlineWhitespace)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (paragraphs.length < 2) return '';
  return paragraphs.join('\n\n');
}

String _upgradeStructuredSingleNewlinesToParagraphs(String raw) {
  if (raw.contains('\n\n')) return '';
  if (!raw.contains('\n')) return '';
  final lines = raw
      .split('\n')
      .map(_compactInlineWhitespace)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 2) return '';
  final structuredLineCount =
      lines.where(_looksLikeStructuredTranscriptLine).length;
  if (structuredLineCount < 2) return '';
  if (structuredLineCount * 2 < lines.length) return '';
  return lines.join('\n\n');
}

String _compactInlineWhitespace(String raw) {
  return raw.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
}

String _paragraphizeTranscriptWithTurnHints(String raw,
    {required int turnCount}) {
  final sentences = _splitTranscriptSentences(raw);
  if (sentences.length < 2) {
    return '';
  }

  final paragraphCount = _targetParagraphCount(
    text: raw,
    sentenceCount: sentences.length,
    turnCount: turnCount,
  );
  if (paragraphCount < 2) {
    return '';
  }

  final paragraphs = _distributeSentencesIntoParagraphs(
    sentences,
    paragraphCount,
  );
  if (paragraphs.length < 2) {
    return '';
  }
  return paragraphs.join('\n\n');
}

String _paragraphizeLineBrokenTranscript(String raw) {
  if (raw.contains('\n\n') || !raw.contains('\n')) {
    return '';
  }

  final lines = raw
      .split('\n')
      .map(_compactInlineWhitespace)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 4) {
    return '';
  }

  final sentenceLikeLineCount = lines.where(_looksLikeSentenceLine).length;
  if (sentenceLikeLineCount * 4 < lines.length * 3) {
    return '';
  }

  final sentences = _splitTranscriptSentences(raw);
  if (sentences.length < 2) {
    return '';
  }

  final paragraphCount =
      ((lines.length + 3) / 4).ceil().clamp(2, sentences.length);
  final paragraphs = _distributeSentencesIntoParagraphs(
    sentences,
    paragraphCount,
  );
  if (paragraphs.length < 2) {
    return '';
  }
  return paragraphs.join('\n\n');
}

List<String> _splitTranscriptSentences(String raw) {
  final normalized = _compactInlineWhitespace(raw);
  if (normalized.isEmpty) return const <String>[];

  final sentences = <String>[];
  var buffer = StringBuffer();
  for (var i = 0; i < normalized.length; i += 1) {
    final char = normalized[i];
    buffer.write(char);
    if (!_isSentenceTerminalAt(normalized, i)) {
      continue;
    }
    while (i + 1 < normalized.length && _isSentenceCloser(normalized[i + 1])) {
      i += 1;
      buffer.write(normalized[i]);
    }
    final sentence = buffer.toString().trim();
    if (sentence.isNotEmpty) {
      sentences.add(sentence);
    }
    buffer = StringBuffer();
  }

  final trailing = buffer.toString().trim();
  if (trailing.isNotEmpty) {
    sentences.add(trailing);
  }
  return sentences;
}

bool _isSentenceTerminalAt(String text, int index) {
  final char = text[index];
  if (char == '.') {
    return _looksLikePeriodSentenceBoundary(text, index);
  }
  return _isSentenceTerminal(char);
}

bool _isSentenceTerminal(String char) {
  return char == '.' ||
      char == '!' ||
      char == '?' ||
      char == '。' ||
      char == '！' ||
      char == '？';
}

bool _isSentenceCloser(String char) {
  return char == '"' ||
      char == '\'' ||
      char == ')' ||
      char == ']' ||
      char == '}' ||
      char == '”' ||
      char == '’' ||
      char == '）' ||
      char == '】' ||
      char == '』' ||
      char == '」';
}

bool _looksLikePeriodSentenceBoundary(String text, int index) {
  if (index < 0 || index >= text.length || text[index] != '.') {
    return false;
  }
  if (index == text.length - 1) {
    return true;
  }

  final nextChar = text[index + 1];
  if (_isSentenceCloser(nextChar)) {
    return true;
  }
  if (!_isWhitespaceChar(nextChar)) {
    return false;
  }
  final token = _tokenEndingAtPeriod(text, index);
  if (_looksLikeAbbreviation(token)) {
    return false;
  }
  return true;
}

String _tokenEndingAtPeriod(String text, int index) {
  var start = index;
  while (start > 0) {
    final previous = text[start - 1];
    if (!_isAsciiLetter(previous) && previous != '.') {
      break;
    }
    start -= 1;
  }
  return text.substring(start, index + 1);
}

bool _looksLikeAbbreviation(String token) {
  final normalized = token.trim();
  if (normalized.isEmpty) return false;
  final lower = normalized.toLowerCase();
  if (const <String>{
    'dr.',
    'mr.',
    'mrs.',
    'ms.',
    'prof.',
    'sr.',
    'jr.',
    'st.',
    'vs.',
    'etc.',
    'no.',
  }.contains(lower)) {
    return true;
  }
  return RegExp(r'^(?:[a-z]\.){2,}$', caseSensitive: false).hasMatch(
    normalized,
  );
}

bool _looksLikeStructuredTranscriptLine(String line) {
  if (_looksLikeTimestampedTranscriptLine(line)) {
    return true;
  }

  final colonMatch = RegExp(r'[:：]').firstMatch(line);
  if (colonMatch == null) return false;

  final prefix = line.substring(0, colonMatch.start).trim();
  if (prefix.isEmpty || prefix.length > 24) return false;
  if (prefix.contains(RegExp(r'[.!?。！？]'))) return false;
  if (prefix.split(RegExp(r'\s+')).length > 4) return false;
  return true;
}

bool _looksLikeTimestampedTranscriptLine(String line) {
  return RegExp(
    r'^\[?\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?(?:\s*[-–]\s*\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d+)?)?\]?(?:\s+|$)',
  ).hasMatch(line);
}

bool _looksLikeSentenceLine(String line) {
  final normalized = line.trim();
  if (normalized.isEmpty) {
    return false;
  }

  final lastChar = _lastSemanticChar(normalized);
  if (lastChar == null) {
    return false;
  }
  return _isSentenceTerminal(lastChar) || _isSentenceCloser(lastChar);
}

int _targetParagraphCount({
  required String text,
  required int sentenceCount,
  required int turnCount,
}) {
  if (sentenceCount < 2 || turnCount < 2) return 1;
  final bySentence = (sentenceCount / 2).ceil();
  final byLength = (text.length / 180).ceil();
  final upperBound = sentenceCount < turnCount ? sentenceCount : turnCount;
  final desired = bySentence > byLength ? bySentence : byLength;
  return desired.clamp(2, upperBound);
}

List<String> _distributeSentencesIntoParagraphs(
  List<String> sentences,
  int paragraphCount,
) {
  if (sentences.isEmpty || paragraphCount <= 0) return const <String>[];

  final lengths = sentences
      .map((item) => item.replaceAll(RegExp(r'\s+'), '').length)
      .toList(growable: false);
  final totalLength = lengths.fold<int>(0, (sum, item) => sum + item);
  final paragraphs = <String>[];
  var nextSentenceIndex = 0;
  var consumedLength = 0;

  while (paragraphs.length < paragraphCount &&
      nextSentenceIndex < sentences.length) {
    final remainingParagraphs = paragraphCount - paragraphs.length;
    final remainingLength = totalLength - consumedLength;
    final targetLength = (remainingLength / remainingParagraphs).ceil();

    final parts = <String>[];
    var paragraphLength = 0;
    while (nextSentenceIndex < sentences.length) {
      final sentence = sentences[nextSentenceIndex];
      final sentenceLength = lengths[nextSentenceIndex];
      final remainingSentences = sentences.length - nextSentenceIndex;
      final remainingParagraphSlots = remainingParagraphs - 1;
      final canBreakBeforeSentence = parts.isNotEmpty &&
          remainingParagraphSlots > 0 &&
          remainingSentences > remainingParagraphSlots &&
          paragraphLength + sentenceLength > targetLength;
      if (canBreakBeforeSentence) {
        break;
      }

      parts.add(sentence);
      paragraphLength += sentenceLength;
      nextSentenceIndex += 1;

      final remainingSentencesAfter = sentences.length - nextSentenceIndex;
      final remainingParagraphSlotsAfter = remainingParagraphs - 1;
      final hasEnoughSentencesForRemainder =
          remainingSentencesAfter >= remainingParagraphSlotsAfter;
      if (remainingParagraphSlotsAfter <= 0) {
        continue;
      }
      if (!hasEnoughSentencesForRemainder) {
        continue;
      }
      if (paragraphLength >= targetLength) {
        break;
      }
    }

    if (parts.isEmpty) {
      break;
    }
    paragraphs.add(_joinSentences(parts));
    consumedLength += paragraphLength;
  }

  if (nextSentenceIndex < sentences.length && paragraphs.isNotEmpty) {
    final tail = _joinSentences(sentences.sublist(nextSentenceIndex));
    paragraphs[paragraphs.length - 1] = _joinSentences(<String>[
      paragraphs.last,
      tail,
    ]);
  }
  return paragraphs;
}

String _joinSentences(List<String> sentences) {
  if (sentences.isEmpty) return '';
  final buffer = StringBuffer(sentences.first);
  for (final sentence in sentences.skip(1)) {
    if (_shouldOmitInterSentenceSpace(buffer.toString(), sentence)) {
      buffer.write(sentence);
      continue;
    }
    buffer
      ..write(' ')
      ..write(sentence);
  }
  return buffer.toString();
}

bool _shouldOmitInterSentenceSpace(String previous, String next) {
  final previousChar = _lastSemanticChar(previous);
  final nextChar = _firstSemanticChar(next);
  if (previousChar == null || nextChar == null) return false;
  return _isCjkChar(previousChar) || _isCjkChar(nextChar);
}

String? _firstSemanticChar(String value) {
  for (var i = 0; i < value.length; i += 1) {
    final char = value[i];
    if (_isWhitespaceChar(char) || _isOpeningQuoteOrBracket(char)) {
      continue;
    }
    return char;
  }
  return null;
}

String? _lastSemanticChar(String value) {
  for (var i = value.length - 1; i >= 0; i -= 1) {
    final char = value[i];
    if (_isWhitespaceChar(char) || _isSentenceCloser(char)) {
      continue;
    }
    return char;
  }
  return null;
}

bool _isWhitespaceChar(String char) {
  return char.trim().isEmpty;
}

bool _isAsciiLetter(String char) {
  return RegExp(r'[A-Za-z]').hasMatch(char);
}

bool _isOpeningQuoteOrBracket(String char) {
  return char == '"' ||
      char == '\'' ||
      char == '(' ||
      char == '[' ||
      char == '{' ||
      char == '“' ||
      char == '‘' ||
      char == '（' ||
      char == '【' ||
      char == '『' ||
      char == '「';
}

bool _isCjkChar(String char) {
  return RegExp(
    r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af]',
  ).hasMatch(char);
}
