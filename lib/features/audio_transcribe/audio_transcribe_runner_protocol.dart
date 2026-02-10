part of 'audio_transcribe_runner.dart';

String _audioInputFormatByMimeType(String mimeType) {
  final normalized = mimeType.trim().toLowerCase();
  switch (normalized) {
    case 'audio/mpeg':
      return 'mp3';
    case 'audio/wav':
    case 'audio/wave':
    case 'audio/x-wav':
      return 'wav';
    case 'audio/ogg':
    case 'audio/opus':
      return 'ogg';
    case 'audio/flac':
      return 'flac';
    case 'audio/aac':
      return 'aac';
    case 'audio/mp4':
    case 'audio/m4a':
    case 'audio/x-m4a':
      return 'm4a';
    default:
      return 'mp3';
  }
}

String _multimodalTranscribePrompt(String lang) {
  final trimmed = lang.trim();
  if (trimmed.isEmpty || isAutoAudioTranscribeLang(trimmed)) {
    return 'Transcribe the provided audio and return plain text only.';
  }
  return 'Transcribe the provided audio in language "$trimmed" and return plain text only.';
}

String _normalizeTranscriptText(String text) {
  var trimmed = text.trim();
  if (trimmed.isEmpty) return '';

  if (trimmed.startsWith('```')) {
    trimmed = trimmed
        .replaceFirst(RegExp(r'^```[^\n]*\n?'), '')
        .replaceFirst(RegExp(r'\n?```$'), '')
        .trim();
  }

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is String) return decoded.trim();
    if (decoded is Map) {
      final textCandidate = decoded['text']?.toString().trim();
      if ((textCandidate ?? '').isNotEmpty) return textCandidate!;
      final transcriptCandidate = decoded['transcript']?.toString().trim();
      if ((transcriptCandidate ?? '').isNotEmpty) return transcriptCandidate!;
    }
  } catch (_) {
    // Not JSON, keep text as-is.
  }

  return trimmed;
}

String _chatMessageContentToText(Object? content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is! Map) continue;
      final text = item['text']?.toString() ?? '';
      if (text.trim().isNotEmpty) {
        parts.add(text);
      }
    }
    return parts.join('\n');
  }
  if (content is Map) {
    final text = content['text']?.toString() ?? '';
    if (text.trim().isNotEmpty) return text;
  }
  return content.toString();
}

String _extractChatSseDeltaText(Map<String, Object?> map) {
  final choicesRaw = map['choices'];
  if (choicesRaw is List && choicesRaw.isNotEmpty && choicesRaw.first is Map) {
    final first = Map<String, Object?>.from(choicesRaw.first as Map);
    final deltaRaw = first['delta'];
    if (deltaRaw is Map) {
      final delta = Map<String, Object?>.from(deltaRaw);
      final fromContent = _chatMessageContentToText(delta['content']);
      if (fromContent.trim().isNotEmpty) return fromContent;
      final fromText = _chatMessageContentToText(delta['text']);
      if (fromText.trim().isNotEmpty) return fromText;
    }

    final messageRaw = first['message'];
    if (messageRaw is Map) {
      final message = Map<String, Object?>.from(messageRaw);
      final fromMessage = _chatMessageContentToText(message['content']);
      if (fromMessage.trim().isNotEmpty) return fromMessage;
    }

    final fromChoice = _chatMessageContentToText(first['content']);
    if (fromChoice.trim().isNotEmpty) return fromChoice;
  }

  final fromText = _chatMessageContentToText(map['text']);
  if (fromText.trim().isNotEmpty) return fromText;
  final fromTranscript = _chatMessageContentToText(map['transcript']);
  if (fromTranscript.trim().isNotEmpty) return fromTranscript;
  final fromDelta = _chatMessageContentToText(map['delta']);
  if (fromDelta.trim().isNotEmpty) return fromDelta;
  return '';
}

List<String> _parseSseDataEvents(String raw) {
  final events = <String>[];
  final dataLines = <String>[];

  void flush() {
    if (dataLines.isEmpty) return;
    events.add(dataLines.join('\n'));
    dataLines.clear();
  }

  for (final sourceLine in const LineSplitter().convert(raw)) {
    final line = sourceLine.trimRight();
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trim());
    }
  }
  flush();

  return events;
}

Map<String, Object?> _decodeAudioTranscribeResponseMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, Object?>.from(decoded);
    }
  } catch (_) {
    // Fall back to SSE parser below.
  }

  final events = _parseSseDataEvents(raw);
  if (events.isEmpty) {
    throw StateError('audio_transcribe_invalid_json');
  }

  final transcriptBuffer = StringBuffer();
  Map<String, Object?>? lastMap;
  Map<String, Object?>? usage;

  for (final event in events) {
    final payload = event.trim();
    if (payload.isEmpty || payload == '[DONE]') continue;

    Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      continue;
    }
    if (decoded is! Map) continue;

    final map = Map<String, Object?>.from(decoded);
    lastMap = map;

    final usageRaw = map['usage'];
    if (usageRaw is Map) {
      usage = Map<String, Object?>.from(usageRaw);
    }

    final delta = _extractChatSseDeltaText(map);
    if (delta.trim().isNotEmpty) {
      transcriptBuffer.write(delta);
    }
  }

  final out = Map<String, Object?>.from(lastMap ?? <String, Object?>{});
  final mergedTranscript =
      _normalizeTranscriptText(transcriptBuffer.toString());
  final currentText = (out['text'] ?? '').toString().trim();
  final currentTranscript = (out['transcript'] ?? '').toString().trim();
  if (mergedTranscript.isNotEmpty &&
      currentText.isEmpty &&
      currentTranscript.isEmpty) {
    out['text'] = mergedTranscript;
  }
  if (usage != null && out['usage'] == null) {
    out['usage'] = usage;
  }

  if (out.isEmpty) {
    throw StateError('audio_transcribe_invalid_json');
  }
  return out;
}

String extractAudioTranscriptText(Map<String, Object?> decoded) {
  final directText = decoded['text']?.toString() ?? '';
  final directTranscript = decoded['transcript']?.toString() ?? '';
  var text = _normalizeTranscriptText(
    directText.trim().isNotEmpty ? directText : directTranscript,
  );
  if (text.isNotEmpty) return text;

  final choicesRaw = decoded['choices'];
  if (choicesRaw is List && choicesRaw.isNotEmpty) {
    final first = choicesRaw.first;
    if (first is Map) {
      final message = first['message'];
      if (message is Map) {
        final content = _chatMessageContentToText(message['content']);
        text = _normalizeTranscriptText(content);
      } else {
        final content = _chatMessageContentToText(first['content']);
        text = _normalizeTranscriptText(content);
      }
    }
  }
  if (text.isNotEmpty) return text;
  throw StateError('audio_transcribe_empty_text');
}

List<AudioTranscriptSegment> _parseTranscriptSegments(Object? segmentsRaw) {
  final segments = <AudioTranscriptSegment>[];
  if (segmentsRaw is! List) return segments;
  for (final item in segmentsRaw) {
    if (item is! Map) continue;
    final segText = (item['text'] ?? '').toString().trim();
    if (segText.isEmpty) continue;
    final tMsRaw = item['t_ms'];
    if (tMsRaw is num) {
      segments.add(AudioTranscriptSegment(tMs: tMsRaw.round(), text: segText));
      continue;
    }
    final start = item['start'];
    final tMs = start is num ? (start * 1000).round() : 0;
    segments.add(AudioTranscriptSegment(tMs: tMs, text: segText));
  }
  return segments;
}
