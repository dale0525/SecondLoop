import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

final class ShareDraftInbox {
  static const String urlQueuePrefsKey = 'share_url_draft_queue_v1';

  static final StreamController<void> _pendingDraftEvents =
      StreamController<void>.broadcast();

  static Stream<void> get pendingDraftEvents => _pendingDraftEvents.stream;

  static Future<void> enqueueUrl(String rawUrl) async {
    final normalized = _normalizeHttpUrl(rawUrl);
    if (normalized == null) return;

    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(urlQueuePrefsKey) ?? const <String>[];
    final next = <String>[...current, normalized];
    await prefs.setStringList(urlQueuePrefsKey, next);
    _notifyPendingDraftsChanged();
  }

  static Future<List<String>> consumePendingUrls() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(urlQueuePrefsKey);
    if (current == null || current.isEmpty) {
      return const <String>[];
    }

    await prefs.remove(urlQueuePrefsKey);

    final seen = <String>{};
    final result = <String>[];
    for (final raw in current) {
      final normalized = _normalizeHttpUrl(raw);
      if (normalized == null) continue;
      if (!seen.add(normalized)) continue;
      result.add(normalized);
    }
    return result;
  }

  static String? _normalizeHttpUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.trim().isEmpty) return null;
    return trimmed;
  }

  static void _notifyPendingDraftsChanged() {
    if (_pendingDraftEvents.isClosed) return;
    _pendingDraftEvents.add(null);
  }
}
