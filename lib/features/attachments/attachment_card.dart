import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/attachments/attachment_metadata_store.dart';
import '../../core/backend/native_app_dir.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/api/content_extract.dart' as rust_content_extract;
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import '../../ui/sl_tokens.dart';
import 'attachment_text_source_policy.dart';

class AttachmentCard extends StatelessWidget {
  const AttachmentCard({
    required this.attachment,
    this.onTap,
    super.key,
  });

  final Attachment attachment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(tokens.radiusLg);
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;

    final cardDataFuture = sessionKey == null
        ? null
        : _loadAttachmentCardData(
            sessionKey,
            attachmentSha256: attachment.sha256,
          );

    final child = FutureBuilder(
      future: cardDataFuture,
      builder: (context, snapshot) {
        final cardData = snapshot.data;
        final meta = cardData?.metadata;
        final displayTitle = _resolveDisplayTitle(attachment, meta);
        final isOcrRunning = cardData?.ocrRunning ?? false;
        final preparingText = context.t.sync.progressDialog.preparing;
        final subtitle = _resolveDisplaySummary(
          meta,
          extractedSummary: cardData?.extractedSummary,
          displayTitle: displayTitle,
          fallback: isOcrRunning
              ? context.t.attachments.content.ocrRunning
              : preparingText,
        );
        final showProcessingIndicator =
            isOcrRunning || subtitle == preparingText;
        final icon = _resolveIcon(attachment.mimeType);

        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      if (showProcessingIndicator)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      height: 1.25,
                                    ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.25,
                                  ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (onTap == null) {
      return SlSurface(borderRadius: radius, child: child);
    }

    return SlSurface(
      borderRadius: radius,
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: child,
          ),
        ),
      ),
    );
  }
}

Future<_AttachmentCardData> _loadAttachmentCardData(
  Uint8List sessionKey, {
  required String attachmentSha256,
}) async {
  final metadataFuture = const RustAttachmentMetadataStore()
      .read(sessionKey, attachmentSha256: attachmentSha256)
      .catchError((_) => null);
  final summaryFuture = _readPayloadSummaryFromPayload(
    sessionKey,
    attachmentSha256: attachmentSha256,
  );

  final values = await Future.wait<Object?>([
    metadataFuture,
    summaryFuture,
  ]);
  return _AttachmentCardData(
    metadata: values[0] as AttachmentMetadata?,
    extractedSummary: (values[1] as _AttachmentCardPayloadSummary).summary,
    ocrRunning: (values[1] as _AttachmentCardPayloadSummary).ocrRunning,
  );
}

bool _isAttachmentOcrRunning(Map<String, Object?> payload) {
  final status =
      (payload['ocr_auto_status'] ?? '').toString().trim().toLowerCase();
  if (status == 'running') return true;
  return payload['ocr_running'] == true;
}

Future<_AttachmentCardPayloadSummary> _readPayloadSummaryFromPayload(
  Uint8List sessionKey, {
  required String attachmentSha256,
}) async {
  try {
    final appDir = await getNativeAppDir();
    final payloadJson =
        await rust_content_extract.dbReadAttachmentAnnotationPayloadJson(
      appDir: appDir,
      key: sessionKey,
      attachmentSha256: attachmentSha256,
    );
    final raw = payloadJson?.trim();
    if (raw == null || raw.isEmpty) {
      return const _AttachmentCardPayloadSummary(
        summary: null,
        ocrRunning: false,
      );
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const _AttachmentCardPayloadSummary(
        summary: null,
        ocrRunning: false,
      );
    }
    final payload = Map<String, Object?>.from(decoded);
    final summary = extractAttachmentCardSummaryFromPayload(payload);
    return _AttachmentCardPayloadSummary(
      summary: summary,
      ocrRunning: _isAttachmentOcrRunning(payload),
    );
  } catch (_) {
    return const _AttachmentCardPayloadSummary(
        summary: null, ocrRunning: false);
  }
  return const _AttachmentCardPayloadSummary(summary: null, ocrRunning: false);
}

String _normalizedTextSnippet(String? raw) {
  final text = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

String? extractAttachmentCardSummaryFromPayload(Map<String, Object?> payload) {
  final preferred = selectAttachmentDisplayText(payload);
  final preferredExcerpt = _normalizedTextSnippet(preferred.excerpt);
  if (preferredExcerpt.isNotEmpty) return preferredExcerpt;

  final preferredFull = _normalizedTextSnippet(preferred.full);
  if (preferredFull.isNotEmpty) return preferredFull;

  final transcriptExcerpt = _normalizedTextSnippet(
    payload['transcript_excerpt']?.toString(),
  );
  if (transcriptExcerpt.isNotEmpty) return transcriptExcerpt;

  final captionLong = _normalizedTextSnippet(
    payload['caption_long']?.toString(),
  );
  if (captionLong.isNotEmpty) return captionLong;

  final transcriptFull = _normalizedTextSnippet(
    payload['transcript_full']?.toString(),
  );
  if (transcriptFull.isNotEmpty) return transcriptFull;

  return null;
}

String _resolveDisplayTitle(Attachment attachment, AttachmentMetadata? meta) {
  final filename =
      meta?.filenames.isNotEmpty == true ? meta!.filenames.first.trim() : '';
  if (filename.isNotEmpty) return filename;

  final title = (meta?.title ?? '').trim();
  if (title.isNotEmpty) return title;

  final firstUrl =
      meta?.sourceUrls.isNotEmpty == true ? meta!.sourceUrls.first.trim() : '';
  if (firstUrl.isNotEmpty) return firstUrl;

  return attachment.mimeType;
}

String _resolveDisplaySummary(
  AttachmentMetadata? meta, {
  String? extractedSummary,
  required String displayTitle,
  required String fallback,
}) {
  final normalizedSummary = _normalizedTextSnippet(extractedSummary);
  if (normalizedSummary.isNotEmpty && normalizedSummary != displayTitle) {
    return normalizedSummary;
  }

  final sourceUrl =
      meta?.sourceUrls.isNotEmpty == true ? meta!.sourceUrls.first.trim() : '';
  if (sourceUrl.isNotEmpty && sourceUrl != displayTitle) {
    return sourceUrl;
  }

  final title = (meta?.title ?? '').trim();
  if (title.isNotEmpty && title != displayTitle) {
    return title;
  }

  return fallback;
}

IconData _resolveIcon(String mimeType) {
  if (mimeType == 'application/x.secondloop.url+json') {
    return Icons.link_rounded;
  }
  if (mimeType.startsWith('image/')) return Icons.image_outlined;
  if (mimeType.startsWith('video/')) return Icons.videocam_outlined;
  if (mimeType.startsWith('audio/')) return Icons.graphic_eq_rounded;
  if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  return Icons.description_outlined;
}

final class _AttachmentCardData {
  const _AttachmentCardData({
    required this.metadata,
    required this.extractedSummary,
    required this.ocrRunning,
  });

  final AttachmentMetadata? metadata;
  final String? extractedSummary;
  final bool ocrRunning;
}

final class _AttachmentCardPayloadSummary {
  const _AttachmentCardPayloadSummary({
    required this.summary,
    required this.ocrRunning,
  });

  final String? summary;
  final bool ocrRunning;
}
