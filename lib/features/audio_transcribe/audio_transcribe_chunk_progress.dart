import 'dart:convert';
import 'dart:typed_data';

const String kAudioTranscribeChunkPartialErrorPrefix =
    'audio_transcribe_chunk_partial_v1:';

final class AudioTranscribePartialSegment {
  const AudioTranscribePartialSegment({
    required this.tMs,
    required this.text,
  });

  final int tMs;
  final String text;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      't_ms': tMs,
      'text': text,
    };
  }

  static AudioTranscribePartialSegment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tMs = _parseInt(raw['t_ms']);
    final text = (raw['text'] ?? '').toString().trim();
    if (tMs == null || text.isEmpty) return null;
    return AudioTranscribePartialSegment(tMs: tMs, text: text);
  }
}

final class AudioTranscribePartialChunkResult {
  const AudioTranscribePartialChunkResult({
    required this.index,
    required this.offsetMs,
    required this.durationMs,
    required this.transcriptFull,
    required this.segments,
    this.transcriptDurationMs,
  });

  final int index;
  final int offsetMs;
  final int durationMs;
  final String transcriptFull;
  final List<AudioTranscribePartialSegment> segments;
  final int? transcriptDurationMs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'index': index,
      'offset_ms': offsetMs,
      'duration_ms': durationMs,
      if (transcriptDurationMs != null)
        'transcript_duration_ms': transcriptDurationMs,
      'transcript_full': transcriptFull,
      'segments': segments.map((item) => item.toJson()).toList(growable: false),
    };
  }

  static AudioTranscribePartialChunkResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final index = _parseInt(raw['index']);
    final offsetMs = _parseInt(raw['offset_ms']);
    final durationMs = _parseInt(raw['duration_ms']);
    final transcriptDurationMs = _parseInt(raw['transcript_duration_ms']);
    final transcriptFull = (raw['transcript_full'] ?? '').toString().trim();
    final segmentsRaw = raw['segments'];
    final segments = <AudioTranscribePartialSegment>[];
    if (segmentsRaw is List) {
      for (final item in segmentsRaw) {
        final parsed = AudioTranscribePartialSegment.fromJson(item);
        if (parsed != null) segments.add(parsed);
      }
    }
    if (index == null || offsetMs == null || durationMs == null) return null;
    return AudioTranscribePartialChunkResult(
      index: index,
      offsetMs: offsetMs,
      durationMs: durationMs,
      transcriptDurationMs: transcriptDurationMs,
      transcriptFull: transcriptFull,
      segments: List<AudioTranscribePartialSegment>.unmodifiable(segments),
    );
  }
}

final class AudioTranscribeChunkPartialProgress {
  const AudioTranscribeChunkPartialProgress({
    required this.chunkCount,
    required this.completedResults,
    required this.failedChunkIndices,
    required this.retryError,
  });

  final int chunkCount;
  final List<AudioTranscribePartialChunkResult> completedResults;
  final List<int> failedChunkIndices;
  final String retryError;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'chunk_count': chunkCount,
      'completed_results':
          completedResults.map((item) => item.toJson()).toList(growable: false),
      'failed_chunk_indices': failedChunkIndices.toList(growable: false)
        ..sort(),
      'retry_error': retryError,
    };
  }

  static AudioTranscribeChunkPartialProgress? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final chunkCount = _parseInt(raw['chunk_count']);
    final retryError = (raw['retry_error'] ?? '').toString().trim();
    final completed = <AudioTranscribePartialChunkResult>[];
    final completedRaw = raw['completed_results'];
    if (completedRaw is List) {
      for (final item in completedRaw) {
        final parsed = AudioTranscribePartialChunkResult.fromJson(item);
        if (parsed != null) completed.add(parsed);
      }
    }
    final failed = <int>[];
    final failedRaw = raw['failed_chunk_indices'];
    if (failedRaw is List) {
      for (final item in failedRaw) {
        final parsed = _parseInt(item);
        if (parsed != null) failed.add(parsed);
      }
    }
    if (chunkCount == null || chunkCount <= 0) return null;
    return AudioTranscribeChunkPartialProgress(
      chunkCount: chunkCount,
      completedResults:
          List<AudioTranscribePartialChunkResult>.unmodifiable(completed),
      failedChunkIndices: List<int>.unmodifiable(failed),
      retryError: retryError,
    );
  }
}

final class AudioTranscribePartialMergeResult {
  const AudioTranscribePartialMergeResult({
    required this.transcriptFull,
    required this.transcriptExcerpt,
    required this.segments,
    this.durationMs,
  });

  final String transcriptFull;
  final String transcriptExcerpt;
  final List<AudioTranscribePartialSegment> segments;
  final int? durationMs;
}

String encodeAudioTranscribeChunkPartialProgress(
  AudioTranscribeChunkPartialProgress progress,
) {
  final payload = utf8.encode(jsonEncode(progress.toJson()));
  final encoded =
      base64UrlEncode(Uint8List.fromList(payload)).replaceAll('=', '');
  return '$kAudioTranscribeChunkPartialErrorPrefix$encoded';
}

AudioTranscribeChunkPartialProgress? decodeAudioTranscribeChunkPartialProgress(
  String rawError,
) {
  final trimmed = rawError.trim();
  if (!trimmed.startsWith(kAudioTranscribeChunkPartialErrorPrefix)) {
    return null;
  }
  final encoded =
      trimmed.substring(kAudioTranscribeChunkPartialErrorPrefix.length).trim();
  if (encoded.isEmpty) return null;
  final padded = _padBase64(encoded);
  try {
    final decoded = utf8.decode(base64Url.decode(padded));
    final map = jsonDecode(decoded);
    return AudioTranscribeChunkPartialProgress.fromJson(map);
  } catch (_) {
    return null;
  }
}

AudioTranscribePartialMergeResult mergeAudioTranscribePartialChunkResults(
  Iterable<AudioTranscribePartialChunkResult> chunks,
) {
  final ordered = chunks.toList(growable: false)
    ..sort((a, b) => a.index.compareTo(b.index));

  final transcriptParts = <String>[];
  final mergedSegments = <AudioTranscribePartialSegment>[];
  int? mergedDurationMs;
  for (final chunk in ordered) {
    final text = chunk.transcriptFull.trim();
    if (text.isNotEmpty) {
      transcriptParts.add(text);
    }
    final chunkEndMs = chunk.offsetMs +
        ((chunk.transcriptDurationMs != null && chunk.transcriptDurationMs! > 0)
            ? chunk.transcriptDurationMs!
            : chunk.durationMs);
    if (mergedDurationMs == null || chunkEndMs > mergedDurationMs) {
      mergedDurationMs = chunkEndMs;
    }
    for (final segment in chunk.segments) {
      final segText = segment.text.trim();
      if (segText.isEmpty) continue;
      mergedSegments.add(
        AudioTranscribePartialSegment(
          tMs: chunk.offsetMs + segment.tMs,
          text: segText,
        ),
      );
    }
  }
  mergedSegments.sort((a, b) => a.tMs.compareTo(b.tMs));
  final full = transcriptParts.join('\n');
  return AudioTranscribePartialMergeResult(
    transcriptFull: full,
    transcriptExcerpt: _excerpt(full),
    segments: List<AudioTranscribePartialSegment>.unmodifiable(mergedSegments),
    durationMs: mergedDurationMs,
  );
}

String _excerpt(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  const maxChars = 280;
  if (trimmed.length <= maxChars) return trimmed;
  return '${trimmed.substring(0, maxChars)}...';
}

String _padBase64(String raw) {
  final remainder = raw.length % 4;
  if (remainder == 0) return raw;
  return '$raw${'=' * (4 - remainder)}';
}

int? _parseInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}
