import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/attachments_backend.dart';
import '../../core/session/session_scope.dart';
import '../attachments/attachment_deeplink.dart';
import '../attachments/attachment_draft_send_contract.dart';
import 'chat_markdown_attachment_refs.dart';

class ChatMarkdownAttachmentImage extends StatelessWidget {
  const ChatMarkdownAttachmentImage({
    required this.uri,
    required this.draftAttachments,
    this.alt,
    super.key,
  });

  final Uri uri;
  final List<AttachmentDraftPayload> draftAttachments;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final source = uri.toString();
    final draftRef = parseDraftMarkdownImageRef(source);
    if (draftRef != null) {
      final payload =
          draftAttachments.cast<AttachmentDraftPayload?>().firstWhere(
                (candidate) => candidate?.localId == draftRef.localId,
                orElse: () => null,
              );
      if (payload != null && payload.bytes.isNotEmpty) {
        return _buildImage(Image.memory(payload.bytes, fit: BoxFit.contain));
      }
    }

    final attachmentRef = parseAttachmentDeepLink(source);
    final backend = AppBackendScope.maybeOf(context);
    final AttachmentsBackend? attachmentsBackend =
        backend is AttachmentsBackend ? backend as AttachmentsBackend : null;
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    if (attachmentRef != null &&
        attachmentsBackend != null &&
        sessionKey != null) {
      return FutureBuilder<Uint8List>(
        future: attachmentsBackend.readAttachmentBytes(
          sessionKey,
          sha256: attachmentRef.attachmentSha256,
        ),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return _buildImage(Image.memory(bytes, fit: BoxFit.contain));
          }
          if (snapshot.hasError) {
            return _buildBrokenImage();
          }
          return const SizedBox(
            height: 64,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    final uriData = Uri.tryParse(source);
    if (uriData != null && uriData.scheme == 'data') {
      try {
        final data = UriData.parse(source).contentAsBytes();
        return _buildImage(Image.memory(data, fit: BoxFit.contain));
      } catch (_) {
        return _buildBrokenImage();
      }
    }

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return _buildImage(Image.network(source, fit: BoxFit.contain));
    }

    if (uri.scheme == 'file') {
      return _buildImage(Image.file(File.fromUri(uri), fit: BoxFit.contain));
    }

    if (!uri.hasScheme && source.trim().isNotEmpty) {
      return _buildImage(Image.file(File(source), fit: BoxFit.contain));
    }

    return _buildBrokenImage();
  }

  Widget _buildImage(Image image) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: image,
    );
  }

  Widget _buildBrokenImage() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 18),
          const SizedBox(width: 8),
          Flexible(
              child:
                  Text(alt?.trim().isNotEmpty == true ? alt! : uri.toString())),
        ],
      ),
    );
  }
}
