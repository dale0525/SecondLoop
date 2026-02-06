import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';
import '../url_enrichment/url_enrichment_runner.dart';

class NonImageAttachmentView extends StatelessWidget {
  const NonImageAttachmentView({
    required this.attachment,
    required this.bytes,
    this.metadataFuture,
    this.initialMetadata,
    this.annotationPayloadFuture,
    this.initialAnnotationPayload,
    super.key,
  });

  final Attachment attachment;
  final Uint8List bytes;
  final Future<AttachmentMetadata?>? metadataFuture;
  final AttachmentMetadata? initialMetadata;
  final Future<Map<String, Object?>?>? annotationPayloadFuture;
  final Map<String, Object?>? initialAnnotationPayload;

  static Future<void> _openFullTextDialog(
    BuildContext context, {
    required String title,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
            child: SingleChildScrollView(
              child: SelectableText(text),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.t.common.actions.cancel),
            ),
          ],
        );
      },
    );
  }

  static String? _tryParseUrlManifestUrl(Uint8List bytes) {
    try {
      final raw = utf8.decode(bytes, allowMalformed: false);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final schema = decoded['schema'];
      final url = decoded['url'];
      if (schema is! String || schema.trim() != kSecondLoopUrlManifestSchema) {
        return null;
      }
      if (url is! String) return null;
      final trimmed = url.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  static Widget _buildLabeledValueCard(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final v = value.trim();
    if (v.isEmpty) return const SizedBox.shrink();
    return SlSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          SelectableText(
            v,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static Widget _buildView(
    BuildContext context, {
    required Attachment attachment,
    required Uint8List bytes,
    required AttachmentMetadata? meta,
    required Map<String, Object?>? payload,
  }) {
    final title = (meta?.title ?? payload?['title'])?.toString().trim();
    final manifestUrl = attachment.mimeType == kSecondLoopUrlManifestMimeType
        ? _tryParseUrlManifestUrl(bytes)
        : null;
    final canonicalUrl = payload?['canonical_url']?.toString().trim();

    String? excerpt;
    String? full;
    if (payload != null) {
      excerpt = (payload['readable_text_excerpt'] ??
              payload['extracted_text_excerpt'])
          ?.toString()
          .trim();
      full = (payload['readable_text_full'] ?? payload['extracted_text_full'])
          ?.toString()
          .trim();
    }
    final needsOcr = payload?['needs_ocr'] == true;

    final excerptText = (excerpt ?? '').trim();
    final fullText = (full ?? '').trim();
    final showFullButton = fullText.isNotEmpty &&
        (excerptText.isEmpty || fullText.length > excerptText.length);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SlSurface(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.t.attachments.metadata.format,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      attachment.mimeType,
                      key: const ValueKey('attachment_metadata_format'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.t.attachments.metadata.size,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatBytes(attachment.byteLen.toInt()),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if ((title ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                SlSurface(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
              if ((manifestUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildLabeledValueCard(
                  context,
                  label: context.t.attachments.url.originalUrl,
                  value: manifestUrl!,
                ),
              ],
              if ((canonicalUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildLabeledValueCard(
                  context,
                  label: context.t.attachments.url.canonicalUrl,
                  value: canonicalUrl!,
                ),
              ],
              if (needsOcr) ...[
                const SizedBox(height: 12),
                SlSurface(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.t.attachments.content.needsOcrTitle,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.t.attachments.content.needsOcrSubtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if ((excerpt ?? '').isNotEmpty)
                _buildLabeledValueCard(
                  context,
                  label: context.t.attachments.content.excerpt,
                  value: excerpt!,
                )
              else if ((full ?? '').isNotEmpty)
                _buildLabeledValueCard(
                  context,
                  label: context.t.attachments.content.fullText,
                  value: full!,
                )
              else
                SlSurface(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        context.t.sync.progressDialog.preparing,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              if (showFullButton) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => unawaited(
                      _openFullTextDialog(
                        context,
                        title: context.t.attachments.content.fullText,
                        text: fullText,
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_outlined, size: 18),
                    label: Text(context.t.common.actions.open),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    Widget buildWith(AttachmentMetadata? meta, Map<String, Object?>? payload) {
      return _buildView(
        context,
        attachment: attachment,
        bytes: bytes,
        meta: meta,
        payload: payload,
      );
    }

    if (metadataFuture == null && annotationPayloadFuture == null) {
      return buildWith(initialMetadata, initialAnnotationPayload);
    }

    return FutureBuilder<AttachmentMetadata?>(
      future: metadataFuture,
      initialData: initialMetadata,
      builder: (context, metaSnapshot) {
        return FutureBuilder<Map<String, Object?>?>(
          future: annotationPayloadFuture,
          initialData: initialAnnotationPayload,
          builder: (context, payloadSnapshot) {
            return buildWith(metaSnapshot.data, payloadSnapshot.data);
          },
        );
      },
    );
  }
}
