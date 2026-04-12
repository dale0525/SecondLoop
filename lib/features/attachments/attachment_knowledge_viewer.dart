import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_viewer_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../src/rust/knowledge/models.dart';
import '../../ui/sl_surface.dart';
import '../knowledge_viewer/knowledge_document_models.dart';
import '../knowledge_viewer/knowledge_document_viewer.dart';
import 'attachment_detail_text_content.dart';
import 'attachment_text_editor_card.dart';
import 'attachment_text_source_policy.dart';

const _kSecondLoopUrlManifestMimeType = 'application/x.secondloop.url+json';
const _kSecondLoopVideoManifestMimeType = 'application/x.secondloop.video+json';
const _kKnowledgeViewerCharThreshold = 3200;
const _kKnowledgeViewerLineThreshold = 120;

bool _isLargeKnowledgeViewerText(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.length >= _kKnowledgeViewerCharThreshold) return true;
  final lineCount = '\n'.allMatches(trimmed).length + 1;
  return lineCount >= _kKnowledgeViewerLineThreshold;
}

bool shouldUseAttachmentKnowledgeViewer({
  required Attachment attachment,
  required String text,
}) {
  final normalizedText = text.trim();
  if (normalizedText.isEmpty) return false;
  if (!_isLargeKnowledgeViewerText(normalizedText)) return false;

  final mime = attachment.mimeType.trim().toLowerCase();
  if (mime == _kSecondLoopVideoManifestMimeType) return false;
  if (mime.startsWith('image/')) return false;
  if (mime.startsWith('audio/')) return false;
  if (mime.startsWith('video/')) return false;
  if (attachment.sha256.trim().isEmpty) return false;

  return mime == 'application/pdf' ||
      mime == _kSecondLoopUrlManifestMimeType ||
      mime.startsWith('text/') ||
      mime.contains('json') ||
      mime.contains('xml') ||
      mime.contains('document') ||
      mime.contains('wordprocessingml');
}

List<String> candidateAttachmentKnowledgeDocumentIds(
  Attachment attachment,
  Map<String, Object?>? payload,
  String? preferredContentKind,
) {
  final sha = attachment.sha256.trim();
  if (sha.isEmpty) return const <String>[];

  String? preferredDocumentIdFromKind(String? rawKind) {
    final normalized = (rawKind ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final suffix = switch (normalized) {
      'extracted_text' || 'extracted_text_full' => 'extracted_text',
      'readable_text' || 'readable_text_full' => 'readable_text',
      'ocr_text' || 'ocr_text_full' => 'ocr_text',
      'transcript' || 'transcript_full' => 'transcript',
      'metadata' => 'metadata',
      _ => null,
    };
    if (suffix == null) return null;
    return 'attachment:$sha:$suffix';
  }

  String? fromSelection(AttachmentTextSource source) {
    switch (source) {
      case AttachmentTextSource.extracted:
        return 'attachment:$sha:extracted_text';
      case AttachmentTextSource.readable:
        return 'attachment:$sha:readable_text';
      case AttachmentTextSource.ocr:
        return 'attachment:$sha:ocr_text';
      case AttachmentTextSource.none:
        return null;
    }
  }

  final selected = selectAttachmentDisplayText(payload).source;
  final raw = <String?>[
    preferredDocumentIdFromKind(preferredContentKind),
    preferredDocumentIdFromKind(
      (payload?[kPreferredAttachmentContentKindKey] ?? '').toString(),
    ),
    fromSelection(selected),
    'attachment:$sha:readable_text',
    'attachment:$sha:extracted_text',
    'attachment:$sha:ocr_text',
    'attachment:$sha:metadata',
  ];

  final out = <String>[];
  for (final value in raw) {
    if (value == null || value.isEmpty || out.contains(value)) continue;
    out.add(value);
  }
  return out;
}

class AttachmentKnowledgeContentPane extends StatefulWidget {
  const AttachmentKnowledgeContentPane({
    required this.attachment,
    required this.payload,
    required this.text,
    required this.emptyText,
    this.onSave,
    this.extraAction,
    this.initialContentKind,
    this.initialChunkIndex,
    super.key,
  });

  final Attachment attachment;
  final Map<String, Object?>? payload;
  final String text;
  final String emptyText;
  final Future<void> Function(String value)? onSave;
  final AttachmentTextEditorCardAction? extraAction;
  final String? initialContentKind;
  final int? initialChunkIndex;

  @override
  State<AttachmentKnowledgeContentPane> createState() =>
      _AttachmentKnowledgeContentPaneState();
}

class _AttachmentKnowledgeContentPaneState
    extends State<AttachmentKnowledgeContentPane> {
  Future<_ResolvedKnowledgeDocument?>? _documentFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshDocumentFuture();
  }

  @override
  void didUpdateWidget(covariant AttachmentKnowledgeContentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.sha256 != widget.attachment.sha256 ||
        oldWidget.attachment.mimeType != widget.attachment.mimeType ||
        oldWidget.text != widget.text ||
        oldWidget.payload != widget.payload ||
        oldWidget.initialContentKind != widget.initialContentKind ||
        oldWidget.initialChunkIndex != widget.initialChunkIndex) {
      _refreshDocumentFuture();
    }
  }

  void _refreshDocumentFuture() {
    final backend = AppBackendScope.maybeOf(context);
    final viewerBackend =
        backend == null ? null : maybeKnowledgeViewerBackendFor(backend);
    final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
    _documentFuture = _resolveDocument(
      viewerBackend: viewerBackend,
      sessionKey: sessionKey,
    );
  }

  Future<_ResolvedKnowledgeDocument?> _resolveDocument({
    required KnowledgeViewerBackend? viewerBackend,
    required Uint8List? sessionKey,
  }) async {
    if (viewerBackend == null || sessionKey == null) return null;
    if (!shouldUseAttachmentKnowledgeViewer(
      attachment: widget.attachment,
      text: widget.text,
    )) {
      return null;
    }

    final initialChunkIndex = _resolveInitialChunkIndex(
      explicitChunkIndex: widget.initialChunkIndex,
      payload: widget.payload,
    );

    for (final documentId in candidateAttachmentKnowledgeDocumentIds(
      widget.attachment,
      widget.payload,
      widget.initialContentKind,
    )) {
      try {
        final document = await viewerBackend.getKnowledgeViewerDocument(
          sessionKey,
          documentId: documentId,
        );
        return _ResolvedKnowledgeDocument(
          documentId: documentId,
          document: document,
          initialHighlightedUnitId: _deriveChunkUnitId(
            documentId,
            initialChunkIndex,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Widget _buildFallback() {
    return AttachmentTextEditorCard(
      fieldKeyPrefix: 'attachment_text_full',
      label: context.t.attachments.content.fullText,
      showLabel: false,
      text: widget.text,
      markdown: true,
      emptyText: widget.emptyText,
      extraAction: widget.extraAction,
      onSave: widget.onSave,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!shouldUseAttachmentKnowledgeViewer(
      attachment: widget.attachment,
      text: widget.text,
    )) {
      return _buildFallback();
    }

    final future = _documentFuture;
    if (future == null) return _buildFallback();

    return FutureBuilder<_ResolvedKnowledgeDocument?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SlSurface(
            key: ValueKey('attachment_knowledge_viewer_loading'),
            padding: EdgeInsets.all(16),
            child: SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final resolved = snapshot.data;
        if (resolved == null) return _buildFallback();

        final backend = AppBackendScope.maybeOf(context);
        final viewerBackend =
            backend == null ? null : maybeKnowledgeViewerBackendFor(backend);
        final sessionKey = SessionScope.maybeOf(context)?.sessionKey;
        if (viewerBackend == null || sessionKey == null) {
          return _buildFallback();
        }

        return AttachmentKnowledgeViewer(
          backend: viewerBackend,
          sessionKey: sessionKey,
          documentId: resolved.documentId,
          initialDocument: resolved.document,
          fallbackText: widget.text,
          initialHighlightedUnitId: resolved.initialHighlightedUnitId,
          onSave: widget.onSave,
          extraAction: widget.extraAction,
        );
      },
    );
  }
}

final class _ResolvedKnowledgeDocument {
  const _ResolvedKnowledgeDocument({
    required this.documentId,
    required this.document,
    required this.initialHighlightedUnitId,
  });

  final String documentId;
  final KnowledgeViewerDocument document;
  final String? initialHighlightedUnitId;
}

class AttachmentKnowledgeViewer extends StatelessWidget {
  const AttachmentKnowledgeViewer({
    required this.backend,
    required this.sessionKey,
    required this.documentId,
    required this.initialDocument,
    required this.fallbackText,
    this.initialHighlightedUnitId,
    this.onSave,
    this.extraAction,
    this.pageSize = 48,
    super.key,
  });

  final KnowledgeViewerBackend backend;
  final Uint8List sessionKey;
  final String documentId;
  final KnowledgeViewerDocument initialDocument;
  final String fallbackText;
  final String? initialHighlightedUnitId;
  final Future<void> Function(String value)? onSave;
  final AttachmentTextEditorCardAction? extraAction;
  final int pageSize;

  @override
  Widget build(BuildContext context) {
    final extraActions = extraAction == null
        ? const <KnowledgeDocumentViewerAction>[]
        : <KnowledgeDocumentViewerAction>[
            KnowledgeDocumentViewerAction(
              id: extraAction!.id,
              icon: extraAction!.icon,
              label: extraAction!.label,
              tooltip: extraAction!.tooltip,
              buttonKey: extraAction!.buttonKey,
              onPressed: extraAction!.onPressed,
            ),
          ];

    return KnowledgeDocumentViewer(
      backend: backend,
      sessionKey: sessionKey,
      documentId: documentId,
      initialDocument: initialDocument,
      fallbackText: fallbackText,
      initialHighlightedUnitId: initialHighlightedUnitId,
      onSave: onSave,
      extraActions: extraActions,
      pageSize: pageSize,
    );
  }
}

String? _deriveChunkUnitId(String documentId, int? chunkIndex) {
  if (chunkIndex == null) return null;
  final normalizedDocumentId = documentId.trim();
  if (normalizedDocumentId.isEmpty) return null;
  return '$normalizedDocumentId:chunk:$chunkIndex';
}

int? _resolveInitialChunkIndex({
  required int? explicitChunkIndex,
  required Map<String, Object?>? payload,
}) {
  if (explicitChunkIndex != null) return explicitChunkIndex;
  final raw = payload?[kPreferredAttachmentChunkIndexKey];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse((raw ?? '').toString().trim());
}
