import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/attachments_backend.dart';
import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../media_backup/cloud_media_download.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import 'image_exif_metadata.dart';

class AttachmentViewerPage extends StatefulWidget {
  const AttachmentViewerPage({
    required this.attachment,
    super.key,
  });

  final Attachment attachment;

  @override
  State<AttachmentViewerPage> createState() => _AttachmentViewerPageState();
}

class _AttachmentViewerPageState extends State<AttachmentViewerPage> {
  Future<Uint8List>? _bytesFuture;
  Future<AttachmentExifMetadata?>? _exifFuture;
  bool _attemptedSyncDownload = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytesFuture ??= _loadBytes();
    _exifFuture ??= _loadPersistedExif();
  }

  Future<Uint8List> _loadBytes({bool forceSyncDownload = false}) async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) {
      throw StateError('Attachments backend not available');
    }
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      return await attachmentsBackend.readAttachmentBytes(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
    } catch (_) {
      if (!forceSyncDownload && _attemptedSyncDownload) rethrow;
      _attemptedSyncDownload = true;

      final didDownload = await CloudMediaDownload()
          .downloadAttachmentBytesFromConfiguredSync(context,
              sha256: widget.attachment.sha256);
      if (!didDownload) rethrow;

      return attachmentsBackend.readAttachmentBytes(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
    }
  }

  Future<AttachmentExifMetadata?> _loadPersistedExif() async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) return null;
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    try {
      return await attachmentsBackend.readAttachmentExifMetadata(
        sessionKey,
        sha256: widget.attachment.sha256,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildExifCard(
    BuildContext context, {
    required DateTime? capturedAt,
    required double? latitude,
    required double? longitude,
  }) {
    final hasLocation = latitude != null && longitude != null;
    if (capturedAt == null && !hasLocation) return const SizedBox.shrink();

    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (capturedAt != null) ...[
            Text(
              context.t.attachments.metadata.capturedAt,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              formatCapturedAt(capturedAt),
              key: const ValueKey('attachment_metadata_captured_at'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (capturedAt != null && hasLocation) const SizedBox(height: 10),
          if (hasLocation) ...[
            Text(
              context.t.attachments.metadata.location,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              formatLatLon(latitude, longitude),
              key: const ValueKey('attachment_metadata_location'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytesFuture = _bytesFuture;
    final exifFuture = _exifFuture;
    return Scaffold(
      appBar: AppBar(title: Text(widget.attachment.mimeType)),
      body: bytesFuture == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder(
              future: bytesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.broken_image_outlined, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            context.t.errors
                                .loadFailed(error: '${snapshot.error}'),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _bytesFuture =
                                    _loadBytes(forceSyncDownload: true);
                              });
                            },
                            icon: const Icon(Icons.refresh),
                            label: Text(context.t.common.actions.refresh),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final bytes = snapshot.data;
                if (bytes == null) return const SizedBox.shrink();

                final isImage = widget.attachment.mimeType.startsWith('image/');
                if (!isImage) {
                  return const Center(child: Icon(Icons.attach_file));
                }

                final metadata = tryReadImageExifMetadata(bytes);

                final exifFromBytes = metadata;
                if (exifFromBytes != null) {
                  return Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: InteractiveViewer(
                            child: Image.memory(bytes, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _buildExifCard(
                            context,
                            capturedAt: exifFromBytes.capturedAt,
                            latitude: exifFromBytes.latitude,
                            longitude: exifFromBytes.longitude,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                if (exifFuture == null) {
                  return Center(
                    child: InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  );
                }

                return FutureBuilder<AttachmentExifMetadata?>(
                  future: exifFuture,
                  builder: (context, metaSnapshot) {
                    final meta = metaSnapshot.data;
                    final capturedAtMs = meta?.capturedAtMs;
                    final capturedAt = capturedAtMs == null
                        ? null
                        : DateTime.fromMillisecondsSinceEpoch(
                            capturedAtMs.toInt(),
                            isUtc: true,
                          ).toLocal();
                    return Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: InteractiveViewer(
                              child: Image.memory(bytes, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                        if (meta != null)
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: _buildExifCard(
                                context,
                                capturedAt: capturedAt,
                                latitude: meta.latitude,
                                longitude: meta.longitude,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}
