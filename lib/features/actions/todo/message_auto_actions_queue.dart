import 'dart:async';
import 'dart:typed_data';

import '../../../core/backend/app_backend.dart';
import '../../../src/rust/db.dart';

typedef MessageAutoActionsHandler = Future<void> Function(
  Message message,
  String rawText,
);

final class MessageAutoActionsQueue {
  MessageAutoActionsQueue({
    required AppBackend backend,
    required Uint8List sessionKey,
    required MessageAutoActionsHandler handler,
  })  : _backend = backend,
        _sessionKey = sessionKey,
        _handler = handler;

  final AppBackend _backend;
  final Uint8List _sessionKey;
  final MessageAutoActionsHandler _handler;

  final List<_QueueItem> _queue = <_QueueItem>[];
  bool _running = false;
  bool _disposed = false;

  void enqueue({
    required Message message,
    required String rawText,
    required int createdAtMs,
  }) {
    if (_disposed) return;
    _queue.add(
      _QueueItem(
        message: message,
        rawText: rawText,
        createdAtMs: createdAtMs,
      ),
    );
    _drain();
  }

  void dispose() {
    _disposed = true;
    _queue.clear();
  }

  void _drain() {
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    while (!_disposed) {
      if (_queue.isEmpty) break;

      final item = _queue.removeAt(0);
      Message? currentMessage;
      try {
        currentMessage =
            await _backend.getMessageById(_sessionKey, item.message.id);
      } on UnimplementedError {
        currentMessage = item.message;
      } catch (_) {
        currentMessage = null;
      }
      if (_disposed) break;
      if (currentMessage == null) continue;

      final normalizedCurrentText = currentMessage.content.trim();
      if (normalizedCurrentText != item.normalizedRawText) {
        continue;
      }

      try {
        await _handler(currentMessage, item.rawText);
      } catch (_) {
        // Swallow to avoid blocking subsequent jobs.
      }
    }

    _running = false;
    if (_queue.isNotEmpty && !_disposed) {
      _drain();
    }
  }
}

final class _QueueItem {
  _QueueItem({
    required this.message,
    required this.rawText,
    required this.createdAtMs,
  }) : normalizedRawText = rawText.trim();

  final Message message;
  final String rawText;
  final String normalizedRawText;
  final int createdAtMs;
}
