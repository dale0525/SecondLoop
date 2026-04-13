import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_backend.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/pages.dart';
import '../../ui/sl_surface.dart';
import '../memory/memory_correction_dialog.dart';
import 'knowledge_page_actions_sheet.dart';
import 'knowledge_page_display_text.dart';
import 'knowledge_page_evidence_view.dart';
import 'knowledge_page_history_view.dart';
import 'knowledge_page_lint_view.dart';
import 'knowledge_page_wrong_sheet.dart';

class KnowledgePageDetailPage extends StatefulWidget {
  const KnowledgePageDetailPage({
    required this.pageId,
    super.key,
  });

  final String pageId;

  static Future<void> openPageId(
    BuildContext context, {
    required String pageId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          KnowledgePageDetailPage(pageId: pageId),
        ),
      ),
    );
  }

  @override
  State<KnowledgePageDetailPage> createState() =>
      _KnowledgePageDetailPageState();
}

class _KnowledgePageDetailPageState extends State<KnowledgePageDetailPage> {
  Future<_KnowledgePageDetailViewData>? _future;
  bool _submitting = false;

  KnowledgePagesBackend _pagesBackend() {
    final backend = maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    if (backend == null) {
      throw StateError('knowledge_pages_backend_unavailable');
    }
    return backend;
  }

  Future<_KnowledgePageDetailViewData> _load() async {
    final backend = _pagesBackend();
    final sessionKey = SessionScope.of(context).sessionKey;
    final detail = await backend.getKnowledgePageDetail(
      sessionKey,
      pageId: widget.pageId,
    );
    final allSummaries = await backend.listKnowledgePageSummaries(sessionKey);
    final relatedPages = allSummaries
        .where((page) => detail.page.relatedPageIds.contains(page.pageId))
        .toList(growable: false);
    return _KnowledgePageDetailViewData(
      detail: detail,
      relatedPages: relatedPages,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openCorrectionDialog(KnowledgePageDetail detail) async {
    final draft = await showMemoryCorrectionDialog(
      context,
      initialTitle: detail.page.title,
      initialSummary: detail.page.currentSummary,
      initialBody: detail.page.currentBody,
    );
    if (draft == null) return;
    await _runMutation(
      () => _pagesBackend().correctKnowledgePage(
        SessionScope.of(context).sessionKey,
        pageId: widget.pageId,
        title: draft.title,
        summary: draft.summary,
        body: draft.body ?? detail.page.currentBody,
      ),
    );
  }

  Future<void> _showWrongReasonSheet() async {
    final reason = await showKnowledgePageWrongSheet(context);
    if (reason == null) return;
    await _runMutation(
      () => _pagesBackend().markKnowledgePageWrong(
        SessionScope.of(context).sessionKey,
        pageId: widget.pageId,
        reason: reason,
      ),
    );
  }

  Future<void> _toggleAnswerPolicy(KnowledgePageDetail detail) async {
    await _runMutation(
      () => _pagesBackend().setKnowledgePageAnswerAllowed(
        SessionScope.of(context).sessionKey,
        pageId: widget.pageId,
        allowed: !detail.page.answerPolicy.defaultAllowed,
      ),
    );
  }

  Future<void> _handleOverflowAction(
    KnowledgePageOverflowAction action,
    _KnowledgePageDetailViewData data,
  ) async {
    switch (action) {
      case KnowledgePageOverflowAction.viewEvidence:
        await KnowledgePageEvidenceView.open(
          context,
          pageTitle: data.detail.page.title,
          entries: data.detail.evidenceEntries,
        );
      case KnowledgePageOverflowAction.viewHistory:
        await KnowledgePageHistoryView.open(
          context,
          pageTitle: data.detail.page.title,
          history: data.detail.history,
          versionSnapshots: data.detail.versionSnapshots,
        );
      case KnowledgePageOverflowAction.viewReview:
        await KnowledgePageLintView.open(
          context,
          pageTitle: data.detail.page.title,
          records: data.detail.lintRecords,
        );
      case KnowledgePageOverflowAction.archive:
        await _runMutation(
          () => _pagesBackend().archiveKnowledgePage(
            SessionScope.of(context).sessionKey,
            pageId: widget.pageId,
          ),
        );
      case KnowledgePageOverflowAction.remove:
        await _runMutation(
          () => _pagesBackend().removeKnowledgePage(
            SessionScope.of(context).sessionKey,
            pageId: widget.pageId,
          ),
        );
    }
  }

  Future<void> _runMutation(
    Future<KnowledgePageDetail> Function() action,
  ) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
    });
    try {
      await action();
      if (!mounted) return;
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(context.t.errors.saveFailed(error: '$error')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_KnowledgePageDetailViewData>(
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
        final detail = data.detail;
        final page = detail.page;
        final answerAllowed = page.answerPolicy.defaultAllowed;
        final canToggleAnswerPolicy =
            page.state != KnowledgePageState.archived &&
                page.state != KnowledgePageState.removed;
        return Scaffold(
          appBar: AppBar(
            title: Text(page.title),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded),
                onPressed: _submitting
                    ? null
                    : () async {
                        final action = await showKnowledgePageActionsSheet(
                          context,
                        );
                        if (action == null || !mounted) return;
                        await _handleOverflowAction(action, data);
                      },
              ),
            ],
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
                      page.currentSummary,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (page.currentBody.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(page.currentBody),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PagePill(
                          label: knowledgePageStateLabel(context.t, page.state),
                        ),
                        _PagePill(
                          label:
                              knowledgePageTypeLabel(context.t, page.pageType),
                        ),
                        _PagePill(
                          label: answerAllowed
                              ? context.t.memory.detail.usedByAskAi
                              : context.t.memory.detail.notUsedByAskAi,
                        ),
                        _PagePill(
                          label: knowledgePageUpdatedLabel(
                            context.t,
                            page.updatedAtMs.toInt(),
                          ),
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
                      context.t.memory.detail.actions,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton(
                          onPressed: _submitting
                              ? null
                              : () => unawaited(_openCorrectionDialog(detail)),
                          child: Text(context.t.memory.actions.editMemory),
                        ),
                        OutlinedButton(
                          onPressed: _submitting
                              ? null
                              : () => unawaited(_showWrongReasonSheet()),
                          child: Text(context.t.memory.actions.markInaccurate),
                        ),
                        OutlinedButton(
                          onPressed: _submitting || !canToggleAnswerPolicy
                              ? null
                              : () => unawaited(_toggleAnswerPolicy(detail)),
                          child: Text(
                            answerAllowed
                                ? context.t.memory.actions.stopUsingForAskAi
                                : context.t.memory.actions.useForAskAiAgain,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => KnowledgePageEvidenceView.open(
                            context,
                            pageTitle: page.title,
                            entries: detail.evidenceEntries,
                          ),
                          child: Text(context.t.memory.actions.viewEvidence),
                        ),
                        TextButton(
                          onPressed: () => KnowledgePageHistoryView.open(
                            context,
                            pageTitle: page.title,
                            history: detail.history,
                            versionSnapshots: detail.versionSnapshots,
                          ),
                          child: Text(context.t.memory.actions.viewHistory),
                        ),
                        TextButton(
                          onPressed: () => unawaited(_handleOverflowAction(
                            KnowledgePageOverflowAction.archive,
                            data,
                          )),
                          child: Text(context.t.memory.actions.archivePage),
                        ),
                        TextButton(
                          onPressed: () => unawaited(_handleOverflowAction(
                            KnowledgePageOverflowAction.remove,
                            data,
                          )),
                          child:
                              Text(context.t.memory.actions.permanentlyRemove),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _DetailSection(
                title: context.t.memory.detail.systemStatus,
                children: [
                  Text(
                    context.t.memory.detail.systemStatusBody(
                      pageType:
                          knowledgePageTypeLabel(context.t, page.pageType),
                      confidence:
                          (page.confidenceLevel * 100).round().toString(),
                      sourceCount: page.sourceCount,
                      conflictCount: page.conflictCount,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DetailSection(
                title: context.t.memory.detail.youMayWantToDo,
                children: _buildGuidance(context, detail),
              ),
              const SizedBox(height: 16),
              _DetailSection(
                title: context.t.memory.detail.evidenceBasis,
                children: [
                  Text(
                    context.t.memory.detail.evidenceSummaryBody(
                      sourceCount: detail.evidenceEntries.length,
                      conflictCount: page.conflictCount,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.t.memory.detail.sourceMix(
                      types: _detailSourceMix(context, detail.evidenceEntries),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _latestSupportingEvidenceLine(
                        context, detail.evidenceEntries),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _conflictSummaryLine(context, detail.evidenceEntries),
                  ),
                  const SizedBox(height: 12),
                  ..._buildEvidencePreview(context, detail.evidenceEntries),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => KnowledgePageEvidenceView.open(
                      context,
                      pageTitle: page.title,
                      entries: detail.evidenceEntries,
                    ),
                    child: Text(context.t.memory.actions.viewEvidence),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DetailSection(
                title: context.t.memory.detail.history,
                children: detail.history.isEmpty
                    ? [Text(context.t.memory.emptyState)]
                    : detail.history
                        .take(3)
                        .map(
                          (item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              knowledgePageChangeTypeLabel(
                                context.t,
                                item.changeType,
                              ),
                            ),
                            subtitle: Text(item.reason ??
                                context.t.memory.history.noReason),
                            trailing: Text(
                              knowledgePageUpdatedLabel(
                                context.t,
                                item.createdAtMs.toInt(),
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        )
                        .toList(growable: false),
              ),
              const SizedBox(height: 16),
              _DetailSection(
                title: context.t.memory.detail.versionHistory,
                children: detail.versionSnapshots.isEmpty
                    ? [Text(context.t.memory.detail.noVersionSnapshots)]
                    : detail.versionSnapshots
                        .take(3)
                        .map(
                          (snapshot) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(snapshot.title),
                            subtitle: Text(
                              snapshot.summary.trim().isEmpty
                                  ? snapshot.body
                                  : snapshot.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              knowledgePageUpdatedLabel(
                                context.t,
                                snapshot.createdAtMs.toInt(),
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        )
                        .toList(growable: false),
              ),
              const SizedBox(height: 16),
              _DetailSection(
                title: context.t.memory.detail.relatedPages,
                children: data.relatedPages.isEmpty
                    ? [Text(context.t.memory.emptyState)]
                    : data.relatedPages
                        .map(
                          (related) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(related.title),
                            subtitle: Text(related.currentSummary),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => KnowledgePageDetailPage.openPageId(
                              context,
                              pageId: related.pageId,
                            ),
                          ),
                        )
                        .toList(growable: false),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildGuidance(
      BuildContext context, KnowledgePageDetail detail) {
    final items = <String>[];
    if (detail.page.state == KnowledgePageState.needsReview) {
      items.add(context.t.memory.detail.guidanceNeedsReview);
    }
    if (!detail.page.answerPolicy.defaultAllowed) {
      items.add(context.t.memory.detail.guidanceMutedFromAnswers);
    }
    if (detail.page.lastUsedAtMs != null) {
      items.add(context.t.memory.detail.guidanceUsedRecently);
    }
    if (detail.lintRecords.isNotEmpty) {
      items.add(detail.lintRecords.first.summary);
    }
    if (items.isEmpty) {
      items.add(context.t.memory.detail.guidanceEverythingStable);
    }
    return items
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_bulletLine(item)),
          ),
        )
        .toList(growable: false);
  }
}

String _bulletLine(String value) => '\u2022 $value';

List<Widget> _buildEvidencePreview(
  BuildContext context,
  List<KnowledgePageEvidenceEntry> entries,
) {
  if (entries.isEmpty) {
    return [Text(context.t.memory.detail.noEvidenceEntries)];
  }
  return entries
      .take(3)
      .map(
        (entry) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _bulletLine(
              '${knowledgePageEvidenceKindLabel(context.t, entry.kind)}: ${entry.summary}',
            ),
          ),
        ),
      )
      .toList(growable: false);
}

String _detailSourceMix(
  BuildContext context,
  List<KnowledgePageEvidenceEntry> entries,
) {
  if (entries.isEmpty) {
    return context.t.memory.detail.noEvidenceEntries;
  }
  final buckets = <String, int>{};
  for (final entry in entries) {
    for (final ref in entry.sourceRefIds) {
      final label = _sourceTypeLabel(context, ref);
      buckets.update(label, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  final ordered = buckets.entries.toList()
    ..sort((left, right) => right.value.compareTo(left.value));
  return ordered.take(3).map((entry) => entry.key).join(', ');
}

String _latestSupportingEvidenceLine(
  BuildContext context,
  List<KnowledgePageEvidenceEntry> entries,
) {
  for (final entry in entries) {
    if (entry.kind == KnowledgePageEvidenceKind.support) {
      return '${context.t.memory.detail.latestSupportingEvidence}: ${entry.summary}';
    }
  }
  return context.t.memory.detail.noEvidenceEntries;
}

String _conflictSummaryLine(
  BuildContext context,
  List<KnowledgePageEvidenceEntry> entries,
) {
  final hasConflict = entries.any(
    (entry) => entry.kind == KnowledgePageEvidenceKind.conflict,
  );
  return hasConflict
      ? context.t.memory.detail.conflictingEvidencePresent
      : context.t.memory.detail.conflictingEvidenceAbsent;
}

String _sourceTypeLabel(BuildContext context, String ref) {
  if (ref.startsWith('message:')) {
    return context.t.memory.detail.sourceTypes.message;
  }
  if (ref.startsWith('attachment:')) {
    return context.t.memory.detail.sourceTypes.attachment;
  }
  if (ref.startsWith('generated:') || ref.startsWith('summary:')) {
    return context.t.memory.detail.sourceTypes.summary;
  }
  if (ref.startsWith('transcript:')) {
    return context.t.memory.detail.sourceTypes.transcript;
  }
  return context.t.memory.detail.sourceTypes.evidence;
}

class _KnowledgePageDetailViewData {
  const _KnowledgePageDetailViewData({
    required this.detail,
    required this.relatedPages,
  });

  final KnowledgePageDetail detail;
  final List<KnowledgePageSummary> relatedPages;
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _PagePill extends StatelessWidget {
  const _PagePill({required this.label});

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
