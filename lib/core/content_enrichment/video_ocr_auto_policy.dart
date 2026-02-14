import 'dart:convert';

const String _kVideoManifestMimeType = 'application/x.secondloop.video+json';
const String _kVideoExtractSchemaV1 = 'secondloop.video_extract.v1';

bool shouldAutoRunVideoManifestOcr(
  Map<String, Object?> payload, {
  int? nowMs,
  int runningStaleMs = 3 * 60 * 1000,
  int failureCooldownMs = 2 * 60 * 1000,
}) {
  final schema = (payload['schema'] ?? '').toString().trim().toLowerCase();
  if (schema != _kVideoExtractSchemaV1) {
    return false;
  }

  final mime = (payload['mime_type'] ?? '').toString().trim().toLowerCase();
  if (mime != _kVideoManifestMimeType) {
    return false;
  }

  final needsOcr = payload['needs_ocr'] == true;
  if (!needsOcr) {
    return false;
  }

  final existingEngine = (payload['ocr_engine'] ?? '').toString().trim();
  if (existingEngine.isNotEmpty) {
    return false;
  }

  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final status =
      (payload['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
  if (status == 'running') {
    final runningSince = _asMillis(payload['ocr_auto_running_ms']);
    if (runningSince > 0 && (now - runningSince) < runningStaleMs) {
      return false;
    }
  }

  final lastFailureMs = _asMillis(payload['ocr_auto_last_failure_ms']);
  if (lastFailureMs > 0 && (now - lastFailureMs) < failureCooldownMs) {
    return false;
  }

  return true;
}

String inferVideoContentKind({
  required String transcriptFull,
  required String ocrTextFull,
  required String readableTextFull,
}) {
  final transcript = transcriptFull.trim();
  final ocr = ocrTextFull.trim();
  final readable = readableTextFull.trim();
  if (readable.isEmpty) return 'unknown';

  final transcriptLen = transcript.length;
  final ocrLen = ocr.length;
  final readableLen = readable.length;
  final newlineCount = '\n'.allMatches(readable).length;

  if (transcriptLen >= 900 || ocrLen >= 700 || readableLen >= 1400) {
    return 'knowledge';
  }

  if (newlineCount >= 16 && (transcriptLen >= 300 || ocrLen >= 300)) {
    return 'knowledge';
  }

  final lower = readable.toLowerCase();
  const knowledgeTokens = <String>[
    'chapter',
    'lesson',
    'definition',
    'example',
    'step',
    'workflow',
    'summary',
    '步骤',
    '定义',
    '总结',
    '公式',
    '原理',
  ];
  var hits = 0;
  for (final token in knowledgeTokens) {
    if (lower.contains(token)) {
      hits += 1;
      if (hits >= 2) {
        return 'knowledge';
      }
    }
  }

  return 'non_knowledge';
}

String buildVideoSummaryText(String readableTextFull, {int maxBytes = 1024}) {
  final normalized = readableTextFull.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return '';
  final safeMax = maxBytes <= 0 ? 0 : maxBytes;
  return _truncateUtf8(normalized, safeMax);
}

int _asMillis(Object? raw) {
  if (raw is int) return raw > 0 ? raw : 0;
  if (raw is num) {
    final value = raw.toInt();
    return value > 0 ? value : 0;
  }
  if (raw is String) {
    final value = int.tryParse(raw.trim()) ?? 0;
    return value > 0 ? value : 0;
  }
  return 0;
}

String _truncateUtf8(String text, int maxBytes) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) return text;
  if (maxBytes <= 0) return '';
  var end = maxBytes;
  while (end > 0 && (bytes[end - 1] & 0xC0) == 0x80) {
    end -= 1;
  }
  if (end <= 0) return '';
  return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
}
