import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/app_backend.dart';

final class ShareIngest {
  static const String _queueKey = 'share_ingest_queue_v1';

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
    Future<void> Function(String path, String mimeType)? onImage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_queueKey) ?? const <String>[];
    if (current.isEmpty) return 0;

    var processed = 0;

    final remaining = <String>[];
    String? conversationId;

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
            await onImage(path, mimeType);
            conversationId ??=
                (await backend.getOrCreateMainStreamConversation(sessionKey))
                    .id;
            await backend.insertMessage(
              sessionKey,
              conversationId,
              role: 'user',
              content: 'Shared image ($mimeType)',
            );
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

    if (remaining.isEmpty) {
      await prefs.remove(_queueKey);
    } else {
      await prefs.setStringList(_queueKey, remaining);
    }

    return processed;
  }
}
