import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../media_backup/cloud_media_download.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';

class ChatImageAttachmentThumbnail extends StatefulWidget {
  const ChatImageAttachmentThumbnail({
    required this.attachment,
    required this.onTap,
    super.key,
  });

  final Attachment attachment;
  final VoidCallback onTap;

  @override
  State<ChatImageAttachmentThumbnail> createState() =>
      _ChatImageAttachmentThumbnailState();
}

class _ChatImageAttachmentThumbnailState
    extends State<ChatImageAttachmentThumbnail> {
  final SyncConfigStore _store = SyncConfigStore();
  final Connectivity _connectivity = Connectivity();

  Future<Uint8List?>? _bytesFuture;
  bool _hasBytes = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes().then((v) {
      _hasBytes = v != null;
      return v;
    });
    _listenConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  void _listenConnectivity() {
    try {
      _connectivitySub = _connectivity.onConnectivityChanged.listen((_) {
        if (!mounted) return;
        if (_hasBytes) return;
        unawaited(_maybeRetry());
      });
    } on MissingPluginException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  Future<void> _maybeRetry() async {
    final allowed = await _shouldAutoDownloadNow();
    if (!allowed) return;
    if (!mounted) return;
    setState(() {
      _bytesFuture = _loadBytes().then((v) {
        _hasBytes = v != null;
        return v;
      });
    });
  }

  Future<bool> _shouldAutoDownloadNow() async {
    final wifiOnly = await _store.readChatThumbnailsWifiOnly();
    if (!wifiOnly) return true;

    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return true;
      }
      if (results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.none)) {
        return false;
      }
      return true;
    } on MissingPluginException {
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<Uint8List?> _loadBytes() async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) return null;
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;

    try {
      return await attachmentsBackend.readAttachmentBytes(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
    } catch (_) {
      final allowed = await _shouldAutoDownloadNow();
      if (!allowed) return null;
      if (!mounted) return null;

      final didDownload = await CloudMediaDownload(configStore: _store)
          .downloadAttachmentBytesFromConfiguredSync(
        context,
        sha256: widget.attachment.sha256,
      );
      if (!didDownload) return null;

      try {
        return await attachmentsBackend.readAttachmentBytes(
          sessionKey,
          sha256: widget.attachment.sha256,
        );
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final radius = BorderRadius.circular(tokens.radiusLg);

    return SlSurface(
      borderRadius: radius,
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            child: SizedBox(
              width: 180,
              height: 180,
              child: FutureBuilder(
                future: _bytesFuture,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done) {
                    return _placeholder(
                      context,
                      icon: Icons.image_outlined,
                      showSpinner: true,
                    );
                  }
                  if (bytes == null || bytes.isEmpty) {
                    return _placeholder(
                      context,
                      icon: Icons.image_outlined,
                      showSpinner: false,
                    );
                  }

                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, _, __) {
                      return _placeholder(
                        context,
                        icon: Icons.broken_image_outlined,
                        showSpinner: false,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(
    BuildContext context, {
    required IconData icon,
    required bool showSpinner,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.6),
      ),
      child: Center(
        child: showSpinner
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
