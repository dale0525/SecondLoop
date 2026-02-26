import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';

final class ShareIngestAttachmentMetadata {
  const ShareIngestAttachmentMetadata({
    this.title,
    this.filenames = const <String>[],
    this.sourceUrls = const <String>[],
  });

  final String? title;
  final List<String> filenames;
  final List<String> sourceUrls;

  @override
  bool operator ==(Object other) {
    return other is ShareIngestAttachmentMetadata &&
        other.title == title &&
        _listEqual(other.filenames, filenames) &&
        _listEqual(other.sourceUrls, sourceUrls);
  }

  @override
  int get hashCode => Object.hash(
        title,
        Object.hashAll(filenames),
        Object.hashAll(sourceUrls),
      );

  static bool _listEqual(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

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
    String? filename,
  }) async {
    final trimmedPath = tempPath.trim();
    final trimmedMime = mimeType.trim();
    final trimmedFilename = filename?.trim();
    if (trimmedPath.isEmpty) return;
    if (trimmedMime.isEmpty) return;
    await _enqueuePayload({
      'type': 'image',
      'path': trimmedPath,
      'mimeType': trimmedMime,
      if (trimmedFilename != null && trimmedFilename.isNotEmpty)
        'filename': trimmedFilename,
    });
  }

  static Future<void> enqueueFile({
    required String tempPath,
    required String mimeType,
    String? filename,
  }) async {
    final trimmedPath = tempPath.trim();
    final trimmedMime = mimeType.trim();
    final trimmedFilename = filename?.trim();
    if (trimmedPath.isEmpty) return;
    if (trimmedMime.isEmpty) return;
    await _enqueuePayload({
      'type': 'file',
      'path': trimmedPath,
      'mimeType': trimmedMime,
      if (trimmedFilename != null && trimmedFilename.isNotEmpty)
        'filename': trimmedFilename,
    });
  }

  static Future<void> _enqueuePayload(Map<String, Object?> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_queueKey) ?? const <String>[];
    final next = <String>[...current, jsonEncode(payload)];
    await prefs.setStringList(_queueKey, next);
  }

  static Future<bool> hasPendingPayloads() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_queueKey);
    return current != null && current.isNotEmpty;
  }

  static Future<int> drainQueue(
    AppBackend backend,
    Uint8List sessionKey, {
    void Function()? onMutation,
    Future<String> Function(String path, String mimeType, String? filename)?
        onImage,
    Future<String> Function(String path, String mimeType, String? filename)?
        onFile,
    Future<String> Function(String url)? onUrlManifest,
    Future<void> Function(String attachmentSha256)? onAttachmentLinked,
    Future<void> Function(
      String attachmentSha256,
      ShareIngestAttachmentMetadata metadata,
    )? onUpsertAttachmentMetadata,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_queueKey) ?? const <String>[];
    if (current.isEmpty) return 0;

    var processedImmediate = 0;
    var pendingBatchCount = 0;
    final pendingTextParts = <String>[];
    final pendingAttachmentMetadataBySha =
        <String, ShareIngestAttachmentMetadata>{};
    final pendingDedup = <String, int>{};

    List<String>? remainingAfterFailure;
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
          final content = payload['content'];
          if (content is! String || content.trim().isEmpty) continue;
          final normalized = content.trim();
          final dedupKey = '$type:$normalized';
          if (dedup.containsKey(dedupKey) ||
              pendingDedup.containsKey(dedupKey)) {
            processedImmediate += 1;
            continue;
          }
          pendingTextParts.add(normalized);
          pendingDedup[dedupKey] = now;
          pendingBatchCount += 1;
          break;
        case 'url':
          final content = payload['content'];
          if (content is! String || content.trim().isEmpty) continue;
          final trimmedUrl = content.trim();
          final dedupKey = 'url:$trimmedUrl';
          if (dedup.containsKey(dedupKey) ||
              pendingDedup.containsKey(dedupKey)) {
            processedImmediate += 1;
            continue;
          }
          try {
            String? attachmentSha256;
            if (onUrlManifest != null) {
              attachmentSha256 = await onUrlManifest(trimmedUrl);
            }

            pendingTextParts.add(trimmedUrl);
            if (attachmentSha256 != null &&
                attachmentSha256.trim().isNotEmpty) {
              pendingAttachmentMetadataBySha.update(
                attachmentSha256,
                (existing) => _mergeAttachmentMetadata(
                  existing,
                  ShareIngestAttachmentMetadata(
                    title: trimmedUrl,
                    sourceUrls: [trimmedUrl],
                  ),
                ),
                ifAbsent: () => ShareIngestAttachmentMetadata(
                  title: trimmedUrl,
                  sourceUrls: [trimmedUrl],
                ),
              );
            }
            pendingDedup[dedupKey] = now;
            pendingBatchCount += 1;
          } catch (_) {
            remainingAfterFailure = <String>[...current.skip(i)];
            break outer;
          }
          break;
        case 'image':
          final path = payload['path'];
          final mimeType = payload['mimeType'];
          final filename = payload['filename'];
          if (path is! String || path.trim().isEmpty) continue;
          if (mimeType is! String || mimeType.trim().isEmpty) continue;
          final safeFilename =
              (filename is String && filename.trim().isNotEmpty)
                  ? filename.trim()
                  : null;
          if (onImage == null) {
            remainingAfterFailure = <String>[...current.skip(i)];
            break outer;
          }
          try {
            final sha256 =
                await onImage(path.trim(), mimeType.trim(), safeFilename);
            final dedupKey = 'image:$sha256';
            if (dedup.containsKey(dedupKey) ||
                pendingDedup.containsKey(dedupKey)) {
              processedImmediate += 1;
              continue;
            }

            if (safeFilename != null) {
              pendingAttachmentMetadataBySha.update(
                sha256,
                (existing) => _mergeAttachmentMetadata(
                  existing,
                  ShareIngestAttachmentMetadata(filenames: [safeFilename]),
                ),
                ifAbsent: () =>
                    ShareIngestAttachmentMetadata(filenames: [safeFilename]),
              );
            } else {
              pendingAttachmentMetadataBySha.putIfAbsent(
                sha256,
                () => const ShareIngestAttachmentMetadata(),
              );
            }
            pendingDedup[dedupKey] = now;
            pendingBatchCount += 1;
          } catch (_) {
            remainingAfterFailure = <String>[...current.skip(i)];
            break outer;
          }
          break;
        case 'file':
          final path = payload['path'];
          final mimeType = payload['mimeType'];
          final filename = payload['filename'];
          if (path is! String || path.trim().isEmpty) continue;
          if (mimeType is! String || mimeType.trim().isEmpty) continue;
          final safeFilename =
              (filename is String && filename.trim().isNotEmpty)
                  ? filename.trim()
                  : null;
          if (onFile == null) {
            remainingAfterFailure = <String>[...current.skip(i)];
            break outer;
          }

          try {
            final sha256 =
                await onFile(path.trim(), mimeType.trim(), safeFilename);
            final dedupKey = 'file:$sha256';
            if (dedup.containsKey(dedupKey) ||
                pendingDedup.containsKey(dedupKey)) {
              processedImmediate += 1;
              continue;
            }

            if (safeFilename != null) {
              pendingAttachmentMetadataBySha.update(
                sha256,
                (existing) => _mergeAttachmentMetadata(
                  existing,
                  ShareIngestAttachmentMetadata(filenames: [safeFilename]),
                ),
                ifAbsent: () =>
                    ShareIngestAttachmentMetadata(filenames: [safeFilename]),
              );
            } else {
              pendingAttachmentMetadataBySha.putIfAbsent(
                sha256,
                () => const ShareIngestAttachmentMetadata(),
              );
            }
            pendingDedup[dedupKey] = now;
            pendingBatchCount += 1;
          } catch (_) {
            remainingAfterFailure = <String>[...current.skip(i)];
            break outer;
          }
          break;
        default:
          break;
      }
    }

    final hasPendingBatch = pendingTextParts.isNotEmpty ||
        pendingAttachmentMetadataBySha.isNotEmpty;
    var commitSucceeded = true;
    if (hasPendingBatch) {
      try {
        final conversationId =
            (await backend.getOrCreateLoopHomeConversation(sessionKey)).id;
        final message = await backend.insertMessage(
          sessionKey,
          conversationId,
          role: 'user',
          content: pendingTextParts.join('\n'),
        );
        final attachmentsBackend = backend is AttachmentsBackend
            ? backend as AttachmentsBackend
            : null;
        if (attachmentsBackend != null &&
            pendingAttachmentMetadataBySha.isNotEmpty) {
          for (final entry in pendingAttachmentMetadataBySha.entries) {
            final attachmentSha256 = entry.key;
            await attachmentsBackend.linkAttachmentToMessage(
              sessionKey,
              message.id,
              attachmentSha256: attachmentSha256,
            );
            if (onAttachmentLinked != null) {
              await onAttachmentLinked(attachmentSha256);
            }
            if (onUpsertAttachmentMetadata != null &&
                _hasAttachmentMetadata(entry.value)) {
              await onUpsertAttachmentMetadata(
                attachmentSha256,
                entry.value,
              );
            }
          }
        }
        onMutation?.call();
      } catch (_) {
        commitSucceeded = false;
      }
    }

    var processed = 0;
    final remaining = remainingAfterFailure ?? const <String>[];
    if (!commitSucceeded) {
      processed = 0;
      await _storeDedup(prefs, dedup);
      await prefs.setStringList(_queueKey, current);
      return processed;
    }

    processed = processedImmediate + pendingBatchCount;
    dedup.addAll(pendingDedup);
    await _storeDedup(prefs, dedup);
    if (remaining.isEmpty) {
      await prefs.remove(_queueKey);
    } else {
      await prefs.setStringList(_queueKey, remaining);
    }

    return processed;
  }

  static bool _hasAttachmentMetadata(ShareIngestAttachmentMetadata metadata) {
    final title = metadata.title?.trim() ?? '';
    return title.isNotEmpty ||
        metadata.filenames.isNotEmpty ||
        metadata.sourceUrls.isNotEmpty;
  }

  static ShareIngestAttachmentMetadata _mergeAttachmentMetadata(
    ShareIngestAttachmentMetadata existing,
    ShareIngestAttachmentMetadata incoming,
  ) {
    final existingTitle = existing.title?.trim() ?? '';
    final incomingTitle = incoming.title?.trim() ?? '';

    final mergedFilenames = <String>[];
    final seenFilename = <String>{};
    for (final item in [...existing.filenames, ...incoming.filenames]) {
      final normalized = item.trim();
      if (normalized.isEmpty) continue;
      if (!seenFilename.add(normalized)) continue;
      mergedFilenames.add(normalized);
    }

    final mergedSourceUrls = <String>[];
    final seenSourceUrl = <String>{};
    for (final item in [...existing.sourceUrls, ...incoming.sourceUrls]) {
      final normalized = item.trim();
      if (normalized.isEmpty) continue;
      if (!seenSourceUrl.add(normalized)) continue;
      mergedSourceUrls.add(normalized);
    }

    return ShareIngestAttachmentMetadata(
      title: existingTitle.isNotEmpty
          ? existingTitle
          : (incomingTitle.isNotEmpty ? incomingTitle : null),
      filenames: mergedFilenames,
      sourceUrls: mergedSourceUrls,
    );
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
