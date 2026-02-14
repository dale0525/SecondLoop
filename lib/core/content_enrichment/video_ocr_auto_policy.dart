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
