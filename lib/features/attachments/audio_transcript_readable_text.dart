import '../audio_transcribe/audio_transcribe_turn_view.dart';

import 'audio_transcript_turn_view_display.dart';

String resolveAudioTranscriptReadableFullText(Map<String, Object?>? payload) {
  final raw =
      _normalizeTranscriptText((payload?['transcript_full'] ?? '').toString());
  if (raw.isEmpty) return '';

  final paragraphPreserving = _normalizeExistingParagraphs(raw);
  if (paragraphPreserving.isNotEmpty) {
    return paragraphPreserving;
  }

  final upgradedSingleNewlines = _upgradeSingleNewlinesToParagraphs(raw);
  if (upgradedSingleNewlines.isNotEmpty) {
    return upgradedSingleNewlines;
  }

  final view = resolveAudioTranscriptTurnView(payload);
  if (view == null ||
      view.status != AudioTranscriptTurnViewStatus.ok ||
      view.turns.length < 2) {
    return raw;
  }

  final sentences = _splitTranscriptSentences(raw);
  if (sentences.length < 2) {
    return raw;
  }

  final paragraphCount = _targetParagraphCount(
    text: raw,
    sentenceCount: sentences.length,
    turnCount: view.turns.length,
  );
  if (paragraphCount < 2) {
    return raw;
  }

  final paragraphs = _distributeSentencesIntoParagraphs(
    sentences,
    paragraphCount,
  );
  if (paragraphs.length < 2) {
    return raw;
  }
  return paragraphs.join('\n\n');
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

String _upgradeSingleNewlinesToParagraphs(String raw) {
  if (raw.contains('\n\n')) return '';
  if (!raw.contains('\n')) return '';
  final lines = raw
      .split('\n')
      .map(_compactInlineWhitespace)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 2) return '';
  return lines.join('\n\n');
}

String _compactInlineWhitespace(String raw) {
  return raw.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
}

List<String> _splitTranscriptSentences(String raw) {
  final normalized = _compactInlineWhitespace(raw);
  if (normalized.isEmpty) return const <String>[];

  final sentences = <String>[];
  var buffer = StringBuffer();
  for (var i = 0; i < normalized.length; i += 1) {
    final char = normalized[i];
    buffer.write(char);
    if (!_isSentenceTerminal(char)) {
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
    paragraphs.add(parts.join(' '));
    consumedLength += paragraphLength;
  }

  if (nextSentenceIndex < sentences.length && paragraphs.isNotEmpty) {
    final tail = sentences.sublist(nextSentenceIndex).join(' ');
    paragraphs[paragraphs.length - 1] = '${paragraphs.last} $tail'.trim();
  }
  return paragraphs;
}
