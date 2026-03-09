import 'dart:developer' as developer;

final class AudioTranscriptTurnSourceSegment {
  const AudioTranscriptTurnSourceSegment({
    required this.tMs,
    required this.text,
  });

  final int tMs;
  final String text;
}

enum AudioTranscriptTurnViewStatus {
  ok,
  fallbackNoSegments,
  fallbackBuilderError,
  fallbackInvalidResult,
}

extension AudioTranscriptTurnViewStatusWireName
    on AudioTranscriptTurnViewStatus {
  String get wireName {
    switch (this) {
      case AudioTranscriptTurnViewStatus.ok:
        return 'ok';
      case AudioTranscriptTurnViewStatus.fallbackNoSegments:
        return 'fallback_no_segments';
      case AudioTranscriptTurnViewStatus.fallbackBuilderError:
        return 'fallback_builder_error';
      case AudioTranscriptTurnViewStatus.fallbackInvalidResult:
        return 'fallback_invalid_result';
    }
  }

  static AudioTranscriptTurnViewStatus fromWireName(String raw) {
    switch (raw.trim()) {
      case 'ok':
        return AudioTranscriptTurnViewStatus.ok;
      case 'fallback_no_segments':
        return AudioTranscriptTurnViewStatus.fallbackNoSegments;
      case 'fallback_builder_error':
        return AudioTranscriptTurnViewStatus.fallbackBuilderError;
      case 'fallback_invalid_result':
        return AudioTranscriptTurnViewStatus.fallbackInvalidResult;
      default:
        return AudioTranscriptTurnViewStatus.fallbackInvalidResult;
    }
  }
}

final class AudioTranscriptTurn {
  const AudioTranscriptTurn({
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.segmentCount,
    required this.sourceSegmentStartIndex,
    required this.sourceSegmentEndIndex,
  });

  final int startMs;
  final int endMs;
  final String text;
  final int segmentCount;
  final int sourceSegmentStartIndex;
  final int sourceSegmentEndIndex;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'start_ms': startMs,
      'end_ms': endMs,
      'text': text,
      'segment_count': segmentCount,
      'source_segment_start_index': sourceSegmentStartIndex,
      'source_segment_end_index': sourceSegmentEndIndex,
    };
  }

  static AudioTranscriptTurn? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final startMs = _parseInt(raw['start_ms']);
    final endMs = _parseInt(raw['end_ms']);
    final text = (raw['text'] ?? '').toString().trim();
    final segmentCount = _parseInt(raw['segment_count']) ?? 0;
    final sourceSegmentStartIndex =
        _parseInt(raw['source_segment_start_index']) ?? 0;
    final sourceSegmentEndIndex =
        _parseInt(raw['source_segment_end_index']) ?? 0;
    if (startMs == null || endMs == null || text.isEmpty) return null;
    return AudioTranscriptTurn(
      startMs: startMs,
      endMs: endMs,
      text: text,
      segmentCount: segmentCount,
      sourceSegmentStartIndex: sourceSegmentStartIndex,
      sourceSegmentEndIndex: sourceSegmentEndIndex,
    );
  }
}

final class AudioTranscriptTurnView {
  const AudioTranscriptTurnView({
    required this.builderVersion,
    required this.status,
    required this.turns,
    required this.params,
  });

  final String builderVersion;
  final AudioTranscriptTurnViewStatus status;
  final List<AudioTranscriptTurn> turns;
  final Map<String, Object?> params;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'builder_version': builderVersion,
      'status': status.wireName,
      'turns': turns.map((item) => item.toJson()).toList(growable: false),
      'params': params,
    };
  }

  static AudioTranscriptTurnView? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawBuilderVersion = (raw['builder_version'] ?? '').toString().trim();
    final builderVersion =
        rawBuilderVersion.isEmpty ? 'turns_v1' : rawBuilderVersion;
    final status = AudioTranscriptTurnViewStatusWireName.fromWireName(
      (raw['status'] ?? '').toString(),
    );
    final turns = <AudioTranscriptTurn>[];
    final turnsRaw = raw['turns'];
    if (turnsRaw is List) {
      for (final item in turnsRaw) {
        final parsed = AudioTranscriptTurn.fromJson(item);
        if (parsed != null) {
          turns.add(parsed);
        }
      }
    }
    final params = raw['params'] is Map
        ? Map<String, Object?>.from(raw['params'] as Map)
        : const <String, Object?>{};
    return AudioTranscriptTurnView(
      builderVersion: builderVersion,
      status: status,
      turns: List<AudioTranscriptTurn>.unmodifiable(turns),
      params: Map<String, Object?>.unmodifiable(params),
    );
  }
}

const String kAudioTranscriptTurnViewBuilderVersion = 'turns_v1';

AudioTranscriptTurnView buildAudioTranscriptTurnView(
  Iterable<AudioTranscriptTurnSourceSegment> segments, {
  int hardGapMs = 1600,
  int softGapMs = 800,
  int maxTurnDurationMs = 35000,
  int maxTurnChars = 280,
  int minFragmentChars = 6,
}) {
  final params = <String, Object?>{
    'hard_gap_ms': hardGapMs,
    'soft_gap_ms': softGapMs,
    'max_turn_duration_ms': maxTurnDurationMs,
    'max_turn_chars': maxTurnChars,
    'min_fragment_chars': minFragmentChars,
  };

  try {
    final normalized = <({int index, int tMs, String text})>[];
    var index = 0;
    for (final segment in segments) {
      final text = _normalizeSegmentText(segment.text);
      if (text.isEmpty) {
        index += 1;
        continue;
      }
      normalized.add((index: index, tMs: segment.tMs, text: text));
      index += 1;
    }

    normalized.sort((a, b) {
      final cmp = a.tMs.compareTo(b.tMs);
      return cmp != 0 ? cmp : a.index.compareTo(b.index);
    });
    if (normalized.isEmpty) {
      return AudioTranscriptTurnView(
        builderVersion: kAudioTranscriptTurnViewBuilderVersion,
        status: AudioTranscriptTurnViewStatus.fallbackNoSegments,
        turns: const <AudioTranscriptTurn>[],
        params: Map<String, Object?>.unmodifiable(params),
      );
    }

    final turns = <AudioTranscriptTurn>[];
    var startMs = 0;
    var endMs = 0;
    var sourceStartIndex = 0;
    var sourceEndIndex = 0;
    var partCount = 0;
    var currentTextLength = 0;
    var currentEndsWithStrongPunctuation = false;
    final textBuffer = <String>[];

    void flushTurn() {
      final text = _joinTurnText(textBuffer);
      if (text.isEmpty) return;
      turns.add(
        AudioTranscriptTurn(
          startMs: startMs,
          endMs: endMs,
          text: text,
          segmentCount: partCount,
          sourceSegmentStartIndex: sourceStartIndex,
          sourceSegmentEndIndex: sourceEndIndex,
        ),
      );
    }

    void appendSegment(({int index, int tMs, String text}) segment) {
      if (textBuffer.isEmpty) {
        startMs = segment.tMs;
        sourceStartIndex = segment.index;
        partCount = 0;
        currentTextLength = 0;
      }
      endMs = segment.tMs;
      sourceEndIndex = segment.index;
      partCount += 1;
      if (textBuffer.isNotEmpty) {
        currentTextLength += 1;
      }
      currentTextLength += segment.text.length;
      currentEndsWithStrongPunctuation =
          _endsWithStrongPunctuation(segment.text);
      textBuffer.add(segment.text);
    }

    appendSegment(normalized.first);

    for (final segment in normalized.skip(1)) {
      final gapMs = segment.tMs - endMs;
      final currentDurationMs = endMs - startMs;
      final segmentIsShort =
          _visibleCharCount(segment.text) <= minFragmentChars;
      final shouldSplitHard = gapMs >= hardGapMs ||
          currentDurationMs >= maxTurnDurationMs ||
          currentTextLength >= maxTurnChars;
      final shouldSplitSoft =
          gapMs >= softGapMs && currentEndsWithStrongPunctuation;

      if (shouldSplitHard || (!segmentIsShort && shouldSplitSoft)) {
        flushTurn();
        textBuffer.clear();
        currentTextLength = 0;
        currentEndsWithStrongPunctuation = false;
      }
      appendSegment(segment);
    }

    flushTurn();

    if (turns.isEmpty) {
      return AudioTranscriptTurnView(
        builderVersion: kAudioTranscriptTurnViewBuilderVersion,
        status: AudioTranscriptTurnViewStatus.fallbackInvalidResult,
        turns: const <AudioTranscriptTurn>[],
        params: Map<String, Object?>.unmodifiable(params),
      );
    }

    return AudioTranscriptTurnView(
      builderVersion: kAudioTranscriptTurnViewBuilderVersion,
      status: AudioTranscriptTurnViewStatus.ok,
      turns: List<AudioTranscriptTurn>.unmodifiable(turns),
      params: Map<String, Object?>.unmodifiable(params),
    );
  } catch (error, stackTrace) {
    assert(() {
      developer.log(
        'AudioTranscriptTurnView builder error',
        name: 'audio_transcribe_turn_view',
        error: error,
        stackTrace: stackTrace,
      );
      return true;
    }());
    return AudioTranscriptTurnView(
      builderVersion: kAudioTranscriptTurnViewBuilderVersion,
      status: AudioTranscriptTurnViewStatus.fallbackBuilderError,
      turns: const <AudioTranscriptTurn>[],
      params: Map<String, Object?>.unmodifiable(params),
    );
  }
}

String formatAudioTranscriptTurnViewFull(AudioTranscriptTurnView view) {
  if (view.status != AudioTranscriptTurnViewStatus.ok || view.turns.isEmpty) {
    return '';
  }
  return view.turns
      .map(
        (turn) => '[${_formatTurnTimestampPair(turn.startMs, turn.endMs)}] '
            '${turn.text}',
      )
      .join('\n\n');
}

String excerptAudioTranscriptTurnView(
  AudioTranscriptTurnView view, {
  int maxChars = 280,
}) {
  final full = formatAudioTranscriptTurnViewFull(view).trim();
  if (full.isEmpty) return '';
  if (full.length <= maxChars) return full;
  final cut = full.lastIndexOf(' ', maxChars);
  final breakAt = cut > 0 ? cut : maxChars;
  return '${full.substring(0, breakAt)}…';
}

List<AudioTranscriptTurnSourceSegment>
    audioTranscriptTurnSourceSegmentsFromJson(
  Object? raw,
) {
  if (raw is! List) return const <AudioTranscriptTurnSourceSegment>[];
  final segments = <AudioTranscriptTurnSourceSegment>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final tMs = _parseInt(item['t_ms']);
    final text = (item['text'] ?? '').toString().trim();
    if (tMs == null || text.isEmpty) continue;
    segments.add(AudioTranscriptTurnSourceSegment(tMs: tMs, text: text));
  }
  return List<AudioTranscriptTurnSourceSegment>.unmodifiable(segments);
}

String _normalizeSegmentText(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _joinTurnText(List<String> parts) {
  return parts.where((item) => item.isNotEmpty).join(' ');
}

int _visibleCharCount(String raw) {
  return raw.replaceAll(RegExp(r'\s+'), '').length;
}

bool _endsWithStrongPunctuation(String text) {
  return RegExp(r'[。！？!?]$').hasMatch(text.trim());
}

String _formatTurnTimestampPair(int startMs, int endMs) {
  final useHours = startMs >= 3600000 || endMs >= 3600000;
  return '${_formatTurnTimestamp(startMs, forceHours: useHours)}–'
      '${_formatTurnTimestamp(endMs, forceHours: useHours)}';
}

String _formatTurnTimestamp(int tMs, {bool forceHours = false}) {
  final totalSeconds = tMs < 0 ? 0 : tMs ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (forceHours || hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

int? _parseInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}
