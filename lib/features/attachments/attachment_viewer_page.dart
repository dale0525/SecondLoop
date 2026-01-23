import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/attachments_backend.dart';
import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytesFuture ??= _loadBytes();
  }

  Future<Uint8List> _loadBytes() async {
    final backend = AppBackendScope.of(context);
    if (backend is! AttachmentsBackend) {
      throw StateError('Attachments backend not available');
    }
    final attachmentsBackend = backend as AttachmentsBackend;
    final sessionKey = SessionScope.of(context).sessionKey;
    return attachmentsBackend.readAttachmentBytes(
      sessionKey,
      sha256: widget.attachment.sha256,
    );
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
                    child: Text(
                      context.t.errors.loadFailed(error: '${snapshot.error}'),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final bytes = snapshot.data;
                if (bytes == null) return const SizedBox.shrink();

                final isImage = widget.attachment.mimeType.startsWith('image/');
                if (!isImage) {
                  return const Center(child: Icon(Icons.attach_file));
                }

                return InteractiveViewer(
                  child: Center(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                );
              },
            ),
    );
  }
}
