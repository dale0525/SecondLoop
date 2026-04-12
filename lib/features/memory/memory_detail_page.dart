import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_backend.dart';
import '../../core/backend/knowledge_viewer_backend.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/models.dart';
import '../../ui/sl_surface.dart';
import '../attachments/attachment_deeplink.dart';
import '../attachments/attachment_viewer_page.dart';
import '../chat/message_deeplink.dart';
import '../chat/message_viewer_page.dart';
import '../knowledge_viewer/knowledge_document_viewer_page.dart';
import 'memory_correction_dialog.dart';
import 'memory_center_models.dart';
import 'memory_display_text.dart';

class MemoryDetailPage extends StatefulWidget {
  const MemoryDetailPage({
    required this.documentId,
    this.startInEditMode = false,
    super.key,
  });

  final String documentId;
  final bool startInEditMode;

  static Future<void> openDocumentId(
    BuildContext context, {
    required String documentId,
    bool startInEditMode = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          MemoryDetailPage(
            documentId: documentId,
            startInEditMode: startInEditMode,
          ),
        ),
      ),
    );
  }

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  Future<_MemoryDetailData>? _future;
  bool _didAutoOpenEdit = false;

  Future<_MemoryDetailData> _load() async {
    final viewerBackend =
        maybeKnowledgeViewerBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.of(context).sessionKey;
    if (viewerBackend == null) {
      throw StateError('knowledge_viewer_backend_unavailable');
    }

    final document = await viewerBackend.getKnowledgeViewerDocument(
      sessionKey,
      documentId: widget.documentId,
    );
    List<KnowledgeUnit> sortedUnits;
    if (viewerBackend case RecentKnowledgeViewerBackend recentBackend) {
      sortedUnits = await recentBackend.listRecentKnowledgeViewerUnits(
        sessionKey,
        documentId: widget.documentId,
        unitKind: KnowledgeUnitKind.segment,
        limit: 16,
      );
    } else {
      const pageSize = 48;
      final allUnits = <KnowledgeUnit>[];
      var offset = 0;
      while (true) {
        final page = await viewerBackend.listKnowledgeViewerUnits(
          sessionKey,
          documentId: widget.documentId,
          unitKind: KnowledgeUnitKind.segment,
          limit: pageSize,
          offset: offset,
        );
        allUnits.addAll(page.units);
        if (page.units.length < pageSize || allUnits.length >= page.total) {
          break;
        }
        offset += page.units.length;
      }
      sortedUnits = List<KnowledgeUnit>.from(allUnits)
        ..sort((left, right) => right.updatedAtMs.compareTo(left.updatedAtMs));
    }
    return _MemoryDetailData(document: document, units: sortedUnits);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<void> _openUnitSource(BuildContext context, KnowledgeUnit unit) async {
    final documentId = unit.documentId.trim();
    if (documentId.startsWith('external:')) {
      await KnowledgeDocumentViewerPage.openDocumentId(
        context,
        documentId: documentId,
        initialHighlightedUnitId: unit.unitId,
      );
      return;
    }

    final attachmentSha = unit.anchors.attachmentSha256?.trim() ?? '';
    if (attachmentSha.isNotEmpty) {
      final target = _attachmentCitationTargetForUnit(unit);
      await AttachmentViewerPage.openBySha(
        context,
        attachmentSha256: attachmentSha,
        initialContentKind: target.$1,
        initialChunkIndex: target.$2,
      );
      return;
    }

    final messageId = unit.anchors.messageId?.trim() ?? '';
    if (messageId.isNotEmpty) {
      await MessageViewerPage.openById(context, messageId: messageId);
    }
  }

  Future<void> _submitFeedback(
    ContentKnowledgeDocument document, {
    KnowledgeMemoryStatus? status,
    bool? useForAskAi,
    bool? isDeleted,
    bool? markedInaccurate,
    String? correctedTitle,
    String? correctedSummary,
  }) async {
    final backend = maybeKnowledgeBackendFor(AppBackendScope.of(context));
    if (backend == null) {
      throw StateError('knowledge_backend_unavailable');
    }
    final feedback = document.memoryFeedback;
    await backend.upsertKnowledgeMemoryFeedback(
      SessionScope.of(context).sessionKey,
      documentId: document.documentId,
      status: status ?? feedback.status,
      useForAskAi: useForAskAi ?? feedback.useForAskAi,
      isDeleted: isDeleted ?? feedback.isDeleted,
      markedInaccurate: markedInaccurate ?? feedback.markedInaccurate,
      correctedTitle: correctedTitle ?? feedback.correctedTitle,
      correctedSummary: correctedSummary ?? feedback.correctedSummary,
    );
    if (!mounted) return;
    _reload();
  }

  Future<void> _openEditDialog(ContentKnowledgeDocument document) async {
    final draft = await showMemoryCorrectionDialog(
      context,
      initialTitle:
          document.memoryFeedback.correctedTitle ?? document.title ?? '',
      initialSummary: document.memoryFeedback.correctedSummary ??
          (document.rawText.trim().isNotEmpty
              ? document.rawText
              : (document.summary ?? '')),
    );
    if (draft == null) return;
    await _submitFeedback(
      document,
      status: KnowledgeMemoryStatus.confirmed,
      correctedTitle: draft.title,
      correctedSummary: draft.summary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MemoryDetailData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(context.t.memory.title)),
            body: Center(
              child:
                  Text(context.t.errors.loadFailed(error: '${snapshot.error}')),
            ),
          );
        }

        final data = snapshot.data!;
        final doc = data.document.document;
        final feedback = doc.memoryFeedback;
        final status = effectiveMemoryStatus(doc);
        final title = resolveMemoryDisplayTitle(
          context.t,
          documentId: doc.documentId,
          explicitTitle: doc.title,
          correctedTitle: doc.memoryFeedback.correctedTitle,
        );
        final summary = resolveMemoryDisplaySummary(
          context.t,
          documentId: doc.documentId,
          explicitSummary: doc.summary,
          rawText: doc.rawText,
          correctedSummary: doc.memoryFeedback.correctedSummary,
        );
        final detailBody = resolveMemoryDisplayBody(
          context.t,
          documentId: doc.documentId,
          rawText: doc.rawText,
        );

        if (widget.startInEditMode && !_didAutoOpenEdit) {
          _didAutoOpenEdit = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            unawaited(_openEditDialog(doc));
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SlSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.memory.detail.currentConclusion,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MemoryPill(label: statusLabel(context, status)),
                        if (memoryCenterSectionForData(doc) case final section?)
                          _MemoryPill(
                            label: _sectionLabel(context, section),
                          ),
                        _MemoryPill(
                          label: _updatedLabel(
                            context,
                            updatedAtMs: doc.updatedAtMs.toInt(),
                          ),
                        ),
                        _MemoryPill(
                          label: feedback.useForAskAi
                              ? context.t.memory.detail.usedByAskAi
                              : context.t.memory.detail.notUsedByAskAi,
                        ),
                        if (feedback.markedInaccurate)
                          _MemoryPill(
                            label: context.t.memory.detail.markedInaccurate,
                          ),
                        if (feedback.isDeleted)
                          _MemoryPill(label: context.t.memory.detail.deleted),
                      ],
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(summary),
                    ],
                    if (detailBody.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        detailBody,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SlSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.memory.detail.actions,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (feedback.isDeleted)
                      FilledButton(
                        key: const ValueKey('memory_restore_button'),
                        onPressed: () => _submitFeedback(doc, isDeleted: false),
                        child: Text(context.t.memory.actions.restoreMemory),
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton(
                            key: const ValueKey('memory_edit_button'),
                            onPressed: () => _openEditDialog(doc),
                            child: Text(context.t.memory.actions.editMemory),
                          ),
                          OutlinedButton(
                            key: const ValueKey('memory_inaccurate_button'),
                            onPressed: () => _submitFeedback(
                              doc,
                              markedInaccurate: !feedback.markedInaccurate,
                            ),
                            child: Text(
                              feedback.markedInaccurate
                                  ? context.t.memory.actions.clearInaccurate
                                  : context.t.memory.actions.markInaccurate,
                            ),
                          ),
                          OutlinedButton(
                            key: const ValueKey('memory_use_toggle_button'),
                            onPressed: () => _submitFeedback(
                              doc,
                              useForAskAi: !feedback.useForAskAi,
                            ),
                            child: Text(
                              feedback.useForAskAi
                                  ? context.t.memory.actions.stopUsingForAskAi
                                  : context.t.memory.actions.useForAskAiAgain,
                            ),
                          ),
                          FilledButton.tonal(
                            key: const ValueKey('memory_delete_button'),
                            onPressed: () =>
                                _submitFeedback(doc, isDeleted: true),
                            child: Text(context.t.memory.actions.deleteMemory),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SlSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.memory.detail.evidenceTimeline,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (data.units.isEmpty)
                      Text(context.t.memory.emptyState)
                    else
                      for (final unit in data.units.take(16)) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SlSurface(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _MemoryPill(
                                      label: _unitSourceTypeLabel(
                                        context,
                                        unit,
                                      ),
                                    ),
                                    _MemoryPill(
                                      label: _updatedLabel(
                                        context,
                                        updatedAtMs: unit.updatedAtMs.toInt(),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _unitSourceTitle(context, unit),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _unitSnippet(context, unit),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_unitAnchorLabel(context, unit)
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    _unitAnchorLabel(context, unit),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                                if (_unitHasOpenableSource(unit)) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () =>
                                          _openUnitSource(context, unit),
                                      child: Text(
                                        context.t.chat.answerEvidence.actions
                                            .viewOriginal,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemoryDetailData {
  const _MemoryDetailData({
    required this.document,
    required this.units,
  });

  final KnowledgeViewerDocument document;
  final List<KnowledgeUnit> units;

  String get fallbackTitle {
    final parts = document.document.documentId.split(':');
    if (parts.length >= 3) {
      return parts.sublist(2).join(' ');
    }
    return document.document.documentId;
  }
}

MemoryCardStatus effectiveMemoryStatus(ContentKnowledgeDocument document) {
  switch (document.memoryDisplay?.status ?? document.memoryFeedback.status) {
    case KnowledgeMemoryStatus.confirmed:
      return MemoryCardStatus.confirmed;
    case KnowledgeMemoryStatus.maybeOutdated:
      return MemoryCardStatus.maybeOutdated;
    case KnowledgeMemoryStatus.inferred:
      return MemoryCardStatus.inferred;
    case null:
      break;
  }
  final section = memoryCenterSectionForData(document);
  if (section == MemoryCenterSection.recentEvents) {
    final ageMs = DateTime.now().millisecondsSinceEpoch - document.updatedAtMs;
    if (ageMs > const Duration(days: 30).inMilliseconds) {
      return MemoryCardStatus.maybeOutdated;
    }
  }
  return MemoryCardStatus.inferred;
}

String statusLabel(BuildContext context, MemoryCardStatus status) {
  return switch (status) {
    MemoryCardStatus.confirmed => context.t.memory.status.confirmed,
    MemoryCardStatus.inferred => context.t.memory.status.inferred,
    MemoryCardStatus.maybeOutdated => context.t.memory.status.maybeOutdated,
  };
}

bool _unitHasOpenableSource(KnowledgeUnit unit) {
  final documentId = unit.documentId.trim();
  if (documentId.startsWith('external:')) {
    return true;
  }
  final messageId = unit.anchors.messageId?.trim() ?? '';
  if (parseMessageDeepLink('secondloop://message/$messageId') != null) {
    return true;
  }
  final attachmentSha = unit.anchors.attachmentSha256?.trim() ?? '';
  return parseAttachmentDeepLink('secondloop://attachment/$attachmentSha') !=
      null;
}

(String?, int?) _attachmentCitationTargetForUnit(KnowledgeUnit unit) {
  final documentId = unit.documentId.trim();
  final initialContentKind = switch (documentId.split(':').last) {
    'extracted_text' => 'extracted_text_full',
    'readable_text' => 'readable_text_full',
    'ocr_text' => 'ocr_text_full',
    'transcript' => 'transcript_full',
    'summary' => 'summary',
    'metadata' => 'metadata',
    _ => null,
  };
  final chunkMatch = RegExp(r':chunk:(\d+)$').firstMatch(unit.unitId.trim());
  final initialChunkIndex =
      chunkMatch == null ? null : int.tryParse(chunkMatch.group(1)!);
  return (initialContentKind, initialChunkIndex);
}

String _unitAnchorLabel(BuildContext context, KnowledgeUnit unit) {
  final parts = <String>[];
  final sectionLabel = resolveMemorySectionLabel(
    context.t,
    rawSectionLabel: unit.anchors.sectionLabel,
  );
  if (sectionLabel != null && sectionLabel.isNotEmpty) {
    parts.add(sectionLabel);
  }
  final sourceFilename = unit.anchors.sourceFilename?.trim();
  if (sourceFilename != null && sourceFilename.isNotEmpty) {
    parts.add(sourceFilename);
  }
  final speaker = unit.anchors.speaker?.trim();
  if (speaker != null && speaker.isNotEmpty) {
    parts.add(speaker);
  }
  final messageId = unit.anchors.messageId?.trim();
  if (messageId != null && messageId.isNotEmpty && parts.isEmpty) {
    parts.add('message');
  }
  final attachmentSha = unit.anchors.attachmentSha256?.trim();
  if (attachmentSha != null && attachmentSha.isNotEmpty && parts.isEmpty) {
    parts.add('attachment');
  }
  if (parts.isEmpty) {
    return unit.sourceKind == KnowledgeSourceKind.summary
        ? context.t.memory.detail.sourceTitles.summary
        : unit.unitKind.name;
  }
  return parts.join(' · ');
}

String _unitSnippet(BuildContext context, KnowledgeUnit unit) {
  final raw = unit.rawText.trim();
  if (raw.isNotEmpty) {
    return resolveMemoryDisplayBody(
      context.t,
      documentId: unit.documentId,
      rawText: raw,
    );
  }
  return unit.normalizedText.trim();
}

String _unitSourceTypeLabel(BuildContext context, KnowledgeUnit unit) {
  if ((unit.anchors.attachmentSha256?.trim() ?? '').isNotEmpty) {
    return context.t.memory.detail.sourceTypes.attachment;
  }
  if ((unit.anchors.messageId?.trim() ?? '').isNotEmpty) {
    return context.t.memory.detail.sourceTypes.message;
  }
  return switch (unit.sourceKind) {
    KnowledgeSourceKind.transcript =>
      context.t.memory.detail.sourceTypes.transcript,
    KnowledgeSourceKind.summary => context.t.memory.detail.sourceTypes.summary,
    _ => context.t.memory.detail.sourceTypes.evidence,
  };
}

String _unitSourceTitle(BuildContext context, KnowledgeUnit unit) {
  final filename = unit.anchors.sourceFilename?.trim();
  if (filename != null && filename.isNotEmpty) {
    return filename;
  }
  final sectionLabel = resolveMemorySectionLabel(
    context.t,
    rawSectionLabel: unit.anchors.sectionLabel,
  );
  if (sectionLabel != null && sectionLabel.isNotEmpty) {
    return sectionLabel;
  }
  if ((unit.anchors.attachmentSha256?.trim() ?? '').isNotEmpty) {
    return context.t.memory.detail.sourceTitles.attachment;
  }
  if ((unit.anchors.messageId?.trim() ?? '').isNotEmpty) {
    return context.t.memory.detail.sourceTitles.message;
  }
  return switch (unit.sourceKind) {
    KnowledgeSourceKind.transcript =>
      context.t.memory.detail.sourceTitles.transcript,
    KnowledgeSourceKind.summary => context.t.memory.detail.sourceTitles.summary,
    _ => context.t.memory.detail.sourceTitles.evidence,
  };
}

String _sectionLabel(BuildContext context, MemoryCenterSection section) {
  return switch (section) {
    MemoryCenterSection.preferences => context.t.memory.sections.preferences,
    MemoryCenterSection.people => context.t.memory.sections.people,
    MemoryCenterSection.projects => context.t.memory.sections.projects,
    MemoryCenterSection.topics => context.t.memory.sections.topics,
    MemoryCenterSection.recentEvents => context.t.memory.sections.recentEvents,
  };
}

String _updatedLabel(BuildContext context, {required int updatedAtMs}) {
  final delta = DateTime.now().millisecondsSinceEpoch - updatedAtMs;
  if (delta < const Duration(days: 1).inMilliseconds) {
    return context.t.memory.meta.updatedToday;
  }
  final dayCount = (delta / const Duration(days: 1).inMilliseconds).floor();
  if (dayCount <= 7) {
    return context.t.memory.meta.updatedDaysAgo(count: dayCount);
  }
  final date = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final formatted =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return context.t.memory.meta.updatedOn(date: formatted);
}

class _MemoryPill extends StatelessWidget {
  const _MemoryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}
