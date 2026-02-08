import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'share_ingest.dart';

final class ShareIntentListener extends StatefulWidget {
  const ShareIntentListener({required this.child, super.key});

  final Widget child;

  @override
  State<ShareIntentListener> createState() => _ShareIntentListenerState();
}

final class _ShareIntentListenerState extends State<ShareIntentListener>
    with WidgetsBindingObserver {
  static const MethodChannel _channel =
      MethodChannel('secondloop/share_intent');

  bool _consuming = false;

  bool _looksLikeUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_consumePendingShares());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_consumePendingShares());
    }
  }

  Future<void> _consumePendingShares() async {
    if (_consuming) return;
    _consuming = true;

    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'consumePendingShares',
      );
      if (raw == null || raw.isEmpty) return;

      var enqueuedAny = false;
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final type = map['type'];
        final content = map['content'];
        if (type is! String || content is! String) continue;

        switch (type) {
          case 'url':
            await ShareIngest.enqueueUrl(content);
            enqueuedAny = true;
            break;
          case 'file':
            final mimeType = map['mimeType'];
            final filename = map['filename'];
            final normalizedMimeType =
                mimeType is String && mimeType.trim().isNotEmpty
                    ? mimeType.trim()
                    : 'application/octet-stream';
            await ShareIngest.enqueueFile(
              tempPath: content,
              mimeType: normalizedMimeType,
              filename: filename is String ? filename : null,
            );
            enqueuedAny = true;
            break;
          case 'image':
            final mimeType = map['mimeType'];
            if (mimeType is! String || mimeType.trim().isEmpty) continue;
            await ShareIngest.enqueueImage(
              tempPath: content,
              mimeType: mimeType,
            );
            enqueuedAny = true;
            break;
          case 'text':
          default:
            if (_looksLikeUrl(content)) {
              await ShareIngest.enqueueUrl(content);
            } else {
              await ShareIngest.enqueueText(content);
            }
            enqueuedAny = true;
        }
      }

      if (enqueuedAny) {
        ShareIngest.requestDrain();
      }
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    } finally {
      _consuming = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
