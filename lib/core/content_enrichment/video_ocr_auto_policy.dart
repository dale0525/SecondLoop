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
  final structuredInstructionLines = _countStructuredInstructionLines(readable);

  final lower = readable.toLowerCase();
  const knowledgeTokens = <String>[
    'chapter',
    'lesson',
    'tutorial',
    'how to',
    'definition',
    'example',
    'step',
    'workflow',
    'summary',
    'key point',
    'takeaway',
    '步骤',
    '教程',
    '要点',
    '定义',
    '总结',
    '公式',
    '原理',
    '第一步',
    '第二步',
    '第三步',
  ];
  var tokenHits = 0;
  for (final token in knowledgeTokens) {
    if (lower.contains(token)) {
      tokenHits += 1;
      if (tokenHits >= 2) {
        return 'knowledge';
      }
    }
  }

  final lowSignalShortText = readableLen < 24 &&
      structuredInstructionLines == 0 &&
      tokenHits == 0 &&
      transcriptLen < 24 &&
      ocrLen < 24;
  if (lowSignalShortText) {
    return 'unknown';
  }

  if (transcriptLen >= 900 || ocrLen >= 700 || readableLen >= 1400) {
    return 'knowledge';
  }

  if (newlineCount >= 16 && (transcriptLen >= 300 || ocrLen >= 300)) {
    return 'knowledge';
  }

  if (structuredInstructionLines >= 2 &&
      (readableLen >= 50 || tokenHits >= 1)) {
    return 'knowledge';
  }

  return 'non_knowledge';
}

String buildVideoSummaryText(String readableTextFull, {int maxBytes = 1024}) {
  final normalized = readableTextFull.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return '';
  final safeMax = maxBytes <= 0 ? 0 : maxBytes;
  return _truncateUtf8(normalized, safeMax);
}

int _countStructuredInstructionLines(String text) {
  final lines = text
      .split(RegExp(r'[\n\r]+'))
      .map((line) => line.trim().toLowerCase())
      .where((line) => line.isNotEmpty);

  var count = 0;
  for (final line in lines) {
    if (RegExp(r'^(step\s*\d+\b|[0-9]+[\.)]\s+|第[一二三四五六七八九十0-9]+步)')
        .hasMatch(line)) {
      count += 1;
      continue;
    }
    if (RegExp(r'^(教程|要点|总结|结论|chapter|lesson|summary|conclusion)[:：]')
        .hasMatch(line)) {
      count += 1;
    }
  }
  return count;
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
