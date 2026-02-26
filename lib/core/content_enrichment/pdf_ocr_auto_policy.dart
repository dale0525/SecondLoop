int _asPositiveInt(Object? raw) {
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

bool _asBool(Object? raw) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

bool _hasNonEmptyFailedRanges(Object? raw) {
  if (raw is! List) return false;
  for (final item in raw) {
    if (item is Map && item.isNotEmpty) {
      return true;
    }
    final text = item?.toString().trim() ?? '';
    if (text.isNotEmpty) {
      return true;
    }
  }
  return false;
}

bool shouldAutoRunPdfOcr(
  Map<String, Object?> payload, {
  int autoMaxPages = 0,
  int? nowMs,
  int runningStaleMs = 3 * 60 * 1000,
  int failureCooldownMs = 2 * 60 * 1000,
}) {
  final mime = (payload['mime_type'] ?? '').toString().trim().toLowerCase();
  if (mime != 'application/pdf') return false;

  final pageCount = _asPositiveInt(payload['page_count']);
  if (pageCount <= 0) return false;
  if (autoMaxPages > 0 && pageCount > autoMaxPages) return false;

  final existingEngine = (payload['ocr_engine'] ?? '').toString().trim();
  final allowPartialRetry = _asBool(payload['ocr_partial']) &&
      _hasNonEmptyFailedRanges(payload['ocr_failed_ranges']);
  if (existingEngine.isNotEmpty && !allowPartialRetry) return false;

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
