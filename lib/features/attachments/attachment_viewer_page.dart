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
  bool _attemptedSyncDownload = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytesFuture ??= _loadBytes();
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

  @override
  Widget build(BuildContext context) {
    final bytesFuture = _bytesFuture;
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

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SizedBox(
                      height: 420,
                      child: InteractiveViewer(
                        child: Center(
                          child: Image.memory(bytes, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (metadata != null)
                      SlSurface(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (metadata.capturedAt != null) ...[
                              Text(
                                context.t.attachments.metadata.capturedAt,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatCapturedAt(metadata.capturedAt!),
                                key: const ValueKey(
                                    'attachment_metadata_captured_at'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (metadata.capturedAt != null &&
                                metadata.hasLocation)
                              const SizedBox(height: 10),
                            if (metadata.hasLocation) ...[
                              Text(
                                context.t.attachments.metadata.location,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatLatLon(
                                  metadata.latitude!,
                                  metadata.longitude!,
                                ),
                                key: const ValueKey(
                                    'attachment_metadata_location'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
