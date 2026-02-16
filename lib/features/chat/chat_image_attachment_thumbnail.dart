import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/session/session_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../i18n/strings.g.dart';
import '../attachments/video_keyframe_ocr_worker.dart';
import '../media_backup/cloud_media_download.dart';
import '../media_backup/cloud_media_download_ui.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';

class ChatImageAttachmentThumbnail extends StatefulWidget {
  const ChatImageAttachmentThumbnail({
    required this.attachment,
    required this.attachmentsBackend,
    required this.onTap,
    this.cloudMediaDownload,
    super.key,
  });

  final Attachment attachment;
  final AttachmentsBackend attachmentsBackend;
  final VoidCallback onTap;
  final CloudMediaDownload? cloudMediaDownload;

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
  bool _loadingBytes = false;
  bool _blockedByWifiOnly = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _listenConnectivity();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bytesFuture == null) {
      _startBytesLoad();
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  void _startBytesLoad() {
    _loadingBytes = true;
    _bytesFuture = _loadBytes().then((v) {
      _hasBytes = v != null && v.isNotEmpty;
      return v;
    }).whenComplete(() {
      _loadingBytes = false;
    });
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
    if (_loadingBytes) return;
    final allowed = await _shouldAutoDownloadNow();
    if (!allowed) return;
    if (!mounted) return;
    if (_loadingBytes) return;
    setState(() {
      _startBytesLoad();
    });
  }

  Future<bool> _shouldAutoDownloadNow() async {
    final wifiOnly = await _store.readMediaDownloadsWifiOnly();
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

  static bool _isVideoManifest(String mimeType) {
    return mimeType.trim().toLowerCase() == kSecondLoopVideoManifestMimeType;
  }

  Future<Uint8List?> _loadBytes() async {
    _blockedByWifiOnly = false;
    if (_isVideoManifest(widget.attachment.mimeType)) {
      return _loadVideoManifestPreviewBytes();
    }
    return _readAttachmentBytesBySha(widget.attachment.sha256);
  }

  Future<Uint8List?> _loadVideoManifestPreviewBytes() async {
    final manifestBytes =
        await _readAttachmentBytesBySha(widget.attachment.sha256);
    if (manifestBytes == null || manifestBytes.isEmpty) return null;

    final manifest = parseVideoManifestPayload(manifestBytes);
    if (manifest == null) return null;

    final posterSha = (manifest.posterSha256 ?? '').trim();
    if (posterSha.isNotEmpty) {
      final posterBytes = await _readAttachmentBytesBySha(posterSha);
      if (posterBytes != null && posterBytes.isNotEmpty) {
        return posterBytes;
      }
    }

    for (final frame in manifest.keyframes) {
      final frameSha = frame.sha256.trim();
      if (frameSha.isEmpty) continue;
      final frameBytes = await _readAttachmentBytesBySha(frameSha);
      if (frameBytes != null && frameBytes.isNotEmpty) {
        return frameBytes;
      }
    }

    return null;
  }

  Future<Uint8List?> _readAttachmentBytesBySha(String sha256) async {
    final normalizedSha = sha256.trim();
    if (normalizedSha.isEmpty) return null;

    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      final bytes = await widget.attachmentsBackend.readAttachmentBytes(
        sessionKey,
        sha256: normalizedSha,
      );
      _blockedByWifiOnly = false;
      return bytes;
    } catch (_) {
      if (!mounted) return null;

      final backend = AppBackendScope.maybeOf(context);
      if (backend == null) return null;
      final idTokenGetter =
          CloudAuthScope.maybeOf(context)?.controller.getIdToken;
      final downloader =
          widget.cloudMediaDownload ?? CloudMediaDownload(configStore: _store);

      final result =
          await downloader.downloadAttachmentBytesFromConfiguredSyncWithPolicy(
        backend: backend,
        sessionKey: sessionKey,
        idTokenGetter: idTokenGetter,
        sha256: normalizedSha,
        allowCellular: false,
      );
      final uiError =
          cloudMediaDownloadUiErrorFromFailureReason(result.failureReason);
      if (uiError == CloudMediaDownloadUiError.wifiOnlyBlocked) {
        _blockedByWifiOnly = true;
      }
      if (!result.didDownload) return null;

      try {
        final bytes = await widget.attachmentsBackend.readAttachmentBytes(
          sessionKey,
          sha256: normalizedSha,
        );
        _blockedByWifiOnly = false;
        return bytes;
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final radius = BorderRadius.circular(tokens.radiusLg);
    final isVideoManifest = _isVideoManifest(widget.attachment.mimeType);

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
                      icon: isVideoManifest
                          ? Icons.smart_display_outlined
                          : Icons.image_outlined,
                      statusText: context.t.sync.progressDialog.preparing,
                      showSpinner: true,
                    );
                  }
                  if (bytes == null || bytes.isEmpty) {
                    return _placeholder(
                      context,
                      icon: _blockedByWifiOnly
                          ? Icons.wifi_off_rounded
                          : (isVideoManifest
                              ? Icons.smart_display_outlined
                              : Icons.broken_image_outlined),
                      statusText: _blockedByWifiOnly
                          ? context
                              .t.sync.mediaPreview.chatThumbnailsWifiOnlyTitle
                          : context.t.attachments.content.previewUnavailable,
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
                        statusText:
                            context.t.attachments.content.previewUnavailable,
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
    required String statusText,
    required bool showSpinner,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          height: 1.25,
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.55),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              if (showSpinner)
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 118),
                      child: Text(
                        statusText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                        style: statusStyle,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  statusText,
                  key: const ValueKey('chat_image_attachment_status_text'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: statusStyle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
