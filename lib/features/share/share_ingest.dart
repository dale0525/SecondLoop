import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';

final class ShareIngest {
  static const String _queueKey = 'share_ingest_queue_v1';
  static const String _dedupKey = 'share_ingest_dedup_v1';
  static const int _dedupWindowMs = 5 * 60 * 1000;

  static final StreamController<void> _drainRequests =
      StreamController<void>.broadcast();

  static Stream<void> get drainRequests => _drainRequests.stream;

  static void requestDrain() {
    if (_drainRequests.isClosed) return;
    _drainRequests.add(null);
  }

  static Future<void> enqueueText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _enqueuePayload({'type': 'text', 'content': trimmed});
  }

  static Future<void> enqueueUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    await _enqueuePayload({'type': 'url', 'content': trimmed});
  }

  static Future<void> enqueueImage({
    required String tempPath,
    required String mimeType,
  }) async {
    final trimmedPath = tempPath.trim();
    final trimmedMime = mimeType.trim();
    if (trimmedPath.isEmpty) return;
    if (trimmedMime.isEmpty) return;
    await _enqueuePayload({
      'type': 'image',
      'path': trimmedPath,
      'mimeType': trimmedMime,
    });
  }

  static Future<void> _enqueuePayload(Map<String, Object?> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_queueKey) ?? const <String>[];
    final next = <String>[...current, jsonEncode(payload)];
    await prefs.setStringList(_queueKey, next);
  }

  static Future<int> drainQueue(
    AppBackend backend,
    Uint8List sessionKey, {
    void Function()? onMutation,
    Future<String> Function(String path, String mimeType)? onImage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_queueKey) ?? const <String>[];
    if (current.isEmpty) return 0;

    var processed = 0;

    final remaining = <String>[];
    String? conversationId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final dedup = _loadDedup(prefs, now);

    outer:
    for (var i = 0; i < current.length; i++) {
      final raw = current[i];
      Map<String, Object?> payload;
      try {
        payload = Map<String, Object?>.from(jsonDecode(raw) as Map);
      } catch (_) {
        continue;
      }

      final type = payload['type'];
      if (type is! String) continue;

      switch (type) {
        case 'text':
        case 'url':
          final content = payload['content'];
          if (content is! String || content.trim().isEmpty) continue;
          final dedupKey = '$type:${content.trim()}';
          if (dedup.containsKey(dedupKey)) {
            processed += 1;
            continue;
          }
          try {
            conversationId ??=
                (await backend.getOrCreateMainStreamConversation(sessionKey))
                    .id;
            await backend.insertMessage(
              sessionKey,
              conversationId,
              role: 'user',
              content: content,
            );
            dedup[dedupKey] = now;
            processed += 1;
            onMutation?.call();
          } catch (_) {
            remaining.addAll(current.skip(i));
            break outer;
          }
          break;
        case 'image':
          final path = payload['path'];
          final mimeType = payload['mimeType'];
          if (path is! String || path.trim().isEmpty) continue;
          if (mimeType is! String || mimeType.trim().isEmpty) continue;
          if (onImage == null) {
            remaining.addAll(current.skip(i));
            break outer;
          }
          try {
            final sha256 = await onImage(path, mimeType);
            final dedupKey = 'image:$sha256';
            if (dedup.containsKey(dedupKey)) {
              processed += 1;
              continue;
            }
            conversationId ??=
                (await backend.getOrCreateMainStreamConversation(sessionKey))
                    .id;
            final message = await backend.insertMessage(
              sessionKey,
              conversationId,
              role: 'user',
              content: 'Shared image ($mimeType)',
            );
            final attachmentsBackend = backend is AttachmentsBackend
                ? backend as AttachmentsBackend
                : null;
            if (attachmentsBackend != null) {
              await attachmentsBackend.linkAttachmentToMessage(
                sessionKey,
                message.id,
                attachmentSha256: sha256,
              );
            }
            dedup[dedupKey] = now;
            processed += 1;
            onMutation?.call();
          } catch (_) {
            remaining.addAll(current.skip(i));
            break outer;
          }
          break;
        default:
          break;
      }
    }

    await _storeDedup(prefs, dedup);
    if (remaining.isEmpty) {
      await prefs.remove(_queueKey);
    } else {
      await prefs.setStringList(_queueKey, remaining);
    }

    return processed;
  }

  static Map<String, int> _loadDedup(SharedPreferences prefs, int now) {
    final raw = prefs.getString(_dedupKey);
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final result = <String, int>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final ts = entry.value;
        if (key is! String) continue;
        if (ts is! int) continue;
        if (now - ts > _dedupWindowMs) continue;
        result[key] = ts;
      }
      return result;
    } catch (_) {
      return <String, int>{};
    }
  }

  static Future<void> _storeDedup(
      SharedPreferences prefs, Map<String, int> dedup) async {
    if (dedup.isEmpty) {
      await prefs.remove(_dedupKey);
      return;
    }

    if (dedup.length > 256) {
      final entries = dedup.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final start = entries.length - 256;
      final trimmed = <String, int>{};
      for (final entry in entries.skip(start)) {
        trimmed[entry.key] = entry.value;
      }
      await prefs.setString(_dedupKey, jsonEncode(trimmed));
      return;
    }

    await prefs.setString(_dedupKey, jsonEncode(dedup));
  }
}
