import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import '../memory/memory_display_text.dart';
import '../memory/memory_correction_dialog.dart';
import 'chat_answer_evidence_models.dart';

enum ChatAnswerEvidenceTab {
  directSources,
  memoryCards,
}

Future<void> showChatAnswerEvidenceSheet(
  BuildContext context, {
  required ChatAnswerEvidence evidence,
  ChatAnswerEvidenceTab initialTab = ChatAnswerEvidenceTab.directSources,
  String? highlightedHref,
  required Future<void> Function(String href) onOpenDirectSource,
  required Future<void> Function(String documentId) onOpenMemoryCard,
  Future<ChatAnswerEvidenceMemoryCard?> Function(
    ChatAnswerEvidenceMemoryCard card,
    String title,
    String summary,
  )? onCorrectMemoryCard,
  Future<void> Function(String documentId)? onDisableMemoryCard,
  Future<void> Function(String documentId)? onDeleteMemoryCard,
}) {
  final isWide = MediaQuery.sizeOf(context).width >= 960;
  final child = ChatAnswerEvidencePanel(
    evidence: evidence,
    initialTab: initialTab,
    highlightedHref: highlightedHref,
    onOpenDirectSource: onOpenDirectSource,
    onOpenMemoryCard: onOpenMemoryCard,
    onCorrectMemoryCard: onCorrectMemoryCard,
    onDisableMemoryCard: onDisableMemoryCard,
    onDeleteMemoryCard: onDeleteMemoryCard,
  );

  if (!isWide) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: child,
      ),
    );
  }

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'dismiss',
    barrierColor: Colors.black54,
    pageBuilder: (_, __, ___) => SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          key: const ValueKey('answer_evidence_desktop_drawer'),
          width: 460,
          margin: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                blurRadius: 36,
                color: Color(0x33000000),
                offset: Offset(-8, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    ),
  );
}

class ChatAnswerEvidencePanel extends StatefulWidget {
  const ChatAnswerEvidencePanel({
    required this.evidence,
    required this.initialTab,
    required this.onOpenDirectSource,
    required this.onOpenMemoryCard,
    this.onCorrectMemoryCard,
    this.onDisableMemoryCard,
    this.onDeleteMemoryCard,
    this.highlightedHref,
    super.key,
  });

  final ChatAnswerEvidence evidence;
  final ChatAnswerEvidenceTab initialTab;
  final String? highlightedHref;
  final Future<void> Function(String href) onOpenDirectSource;
  final Future<void> Function(String documentId) onOpenMemoryCard;
  final Future<ChatAnswerEvidenceMemoryCard?> Function(
    ChatAnswerEvidenceMemoryCard card,
    String title,
    String summary,
  )? onCorrectMemoryCard;
  final Future<void> Function(String documentId)? onDisableMemoryCard;
  final Future<void> Function(String documentId)? onDeleteMemoryCard;

  @override
  State<ChatAnswerEvidencePanel> createState() =>
      _ChatAnswerEvidencePanelState();
}

class _ChatAnswerEvidencePanelState extends State<ChatAnswerEvidencePanel> {
  final Set<String> _disabledMemoryIds = <String>{};
  final Set<String> _deletedMemoryIds = <String>{};
  late List<ChatAnswerEvidenceMemoryCard> _memoryCards;

  @override
  void initState() {
    super.initState();
    _memoryCards = List<ChatAnswerEvidenceMemoryCard>.from(
      widget.evidence.memoryCards,
    );
  }

  @override
  void didUpdateWidget(covariant ChatAnswerEvidencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
        oldWidget.evidence.memoryCards, widget.evidence.memoryCards)) {
      _memoryCards = List<ChatAnswerEvidenceMemoryCard>.from(
        widget.evidence.memoryCards,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = <ChatAnswerEvidenceTab>[
      if (widget.evidence.directSources.isNotEmpty)
        ChatAnswerEvidenceTab.directSources,
      if (_memoryCards.isNotEmpty) ChatAnswerEvidenceTab.memoryCards,
    ];
    final effectiveInitialTab =
        tabs.contains(widget.initialTab) ? widget.initialTab : tabs.first;

    return DefaultTabController(
      length: tabs.length,
      initialIndex: tabs.indexOf(effectiveInitialTab),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(context.t.chat.answerEvidence.title),
          bottom: TabBar(
            tabs: [
              for (final tab in tabs)
                Tab(
                  text: switch (tab) {
                    ChatAnswerEvidenceTab.directSources =>
                      context.t.chat.answerEvidence.tabs.directSources(
                        count: widget.evidence.directSources.length,
                      ),
                    ChatAnswerEvidenceTab.memoryCards =>
                      context.t.chat.answerEvidence.tabs.memoryCards(
                        count: _memoryCards.length,
                      ),
                  },
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final tab in tabs)
              switch (tab) {
                ChatAnswerEvidenceTab.directSources => _DirectSourceList(
                    evidence: widget.evidence,
                    highlightedHref: widget.highlightedHref,
                    onOpenDirectSource: widget.onOpenDirectSource,
                  ),
                ChatAnswerEvidenceTab.memoryCards => ListView.separated(
                    key: const ValueKey('answer_evidence_memory_cards'),
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final item = _memoryCards[index];
                      final whyUsed = item.whyUsed?.trim() ?? '';
                      final isDisabled =
                          _disabledMemoryIds.contains(item.documentId);
                      final isDeleted =
                          _deletedMemoryIds.contains(item.documentId);
                      return SlSurface(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _MetaPill(
                                  label: _memoryStatusLabel(
                                    context,
                                    item.status,
                                  ),
                                ),
                                _MetaPill(
                                  label: isDeleted
                                      ? context.t.memory.detail.deleted
                                      : (isDisabled
                                          ? context
                                              .t.memory.detail.notUsedByAskAi
                                          : context
                                              .t.memory.detail.usedByAskAi),
                                ),
                                if (item.sourceCount > 0)
                                  _MetaPill(
                                    label: context.t.chat.answerEvidence.labels
                                        .sourceCount(
                                      count: item.sourceCount,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              resolveMemoryDisplayTitle(
                                context.t,
                                documentId: item.documentId,
                                explicitTitle: item.title,
                              ),
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              resolveMemoryDisplaySummary(
                                context.t,
                                documentId: item.documentId,
                                explicitSummary: item.summary,
                                rawText: item.body ?? item.summary,
                              ),
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (whyUsed.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                context.t.chat.answerEvidence.labels.whyUsed,
                                style: theme.textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _localizedWhyUsed(context, whyUsed),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      widget.onOpenMemoryCard(item.documentId),
                                  child: Text(
                                    context.t.chat.answerEvidence.actions
                                        .inspectMemory,
                                  ),
                                ),
                                if (widget.onCorrectMemoryCard != null)
                                  TextButton(
                                    onPressed: () async {
                                      final draft =
                                          await showMemoryCorrectionDialog(
                                        context,
                                        initialTitle: item.title ?? '',
                                        initialSummary:
                                            item.body ?? item.summary ?? '',
                                      );
                                      if (draft == null) return;
                                      final updated =
                                          await widget.onCorrectMemoryCard!(
                                        item,
                                        draft.title,
                                        draft.summary,
                                      );
                                      if (!mounted || updated == null) return;
                                      setState(() {
                                        _memoryCards[index] = updated;
                                      });
                                    },
                                    child: Text(
                                      context.t.chat.answerEvidence.actions
                                          .correct,
                                    ),
                                  ),
                                if (widget.onDisableMemoryCard != null &&
                                    !isDeleted)
                                  TextButton(
                                    onPressed: isDisabled
                                        ? null
                                        : () async {
                                            await widget.onDisableMemoryCard!(
                                              item.documentId,
                                            );
                                            if (!mounted) return;
                                            setState(() {
                                              _disabledMemoryIds
                                                  .add(item.documentId);
                                            });
                                          },
                                    child: Text(
                                      context.t.chat.answerEvidence.actions
                                          .dontUse,
                                    ),
                                  ),
                                if (widget.onDeleteMemoryCard != null)
                                  TextButton(
                                    onPressed: isDeleted
                                        ? null
                                        : () async {
                                            await widget.onDeleteMemoryCard!(
                                              item.documentId,
                                            );
                                            if (!mounted) return;
                                            setState(() {
                                              _deletedMemoryIds
                                                  .add(item.documentId);
                                            });
                                          },
                                    child: Text(
                                      context.t.chat.answerEvidence.actions
                                          .deleteMemory,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: _memoryCards.length,
                  ),
              },
          ],
        ),
      ),
    );
  }
}

class _DirectSourceList extends StatelessWidget {
  const _DirectSourceList({
    required this.evidence,
    required this.highlightedHref,
    required this.onOpenDirectSource,
  });

  final ChatAnswerEvidence evidence;
  final String? highlightedHref;
  final Future<void> Function(String href) onOpenDirectSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      key: const ValueKey('answer_evidence_direct_sources'),
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final item = evidence.directSources[index];
        final isHighlighted =
            highlightedHref != null && item.href == highlightedHref;
        return SlSurface(
          color: isHighlighted
              ? theme.colorScheme.secondaryContainer.withOpacity(0.65)
              : null,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaPill(
                    label: '[${index + 1}]',
                  ),
                  _MetaPill(
                    label: _localizedSourceTypeLabel(context, item),
                  ),
                  if ((item.scopeLabel ?? '').trim().isNotEmpty)
                    _MetaPill(
                      label: _localizedScopeLabel(context, item.scopeLabel!),
                    ),
                  if ((item.confidenceLabel ?? '').trim().isNotEmpty)
                    _MetaPill(
                      label: _localizedConfidenceLabel(
                        context,
                        item.confidenceLabel!,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.displayTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                item.displaySnippet,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => onOpenDirectSource(item.href),
                  child: Text(
                    context.t.chat.answerEvidence.actions.viewOriginal,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: evidence.directSources.length,
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.7),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall,
      ),
    );
  }
}

String _memoryStatusLabel(BuildContext context, String rawStatus) {
  switch (rawStatus.trim().toLowerCase()) {
    case 'confirmed':
      return context.t.memory.status.confirmed;
    case 'maybe_outdated':
    case 'maybeoutdated':
      return context.t.memory.status.maybeOutdated;
    case 'inferred':
    default:
      return context.t.memory.status.inferred;
  }
}

String _localizedSourceTypeLabel(
  BuildContext context,
  ChatAnswerEvidenceDirectSource item,
) {
  switch (item.sourceTypeLabel?.trim().toLowerCase()) {
    case 'chat_message':
      return context.t.chat.answerEvidence.sourceTypeLabels.chatMessage;
    case 'attachment':
      return context.t.chat.answerEvidence.sourceTypeLabels.attachment;
    case 'attachment_ocr':
      return context.t.chat.answerEvidence.sourceTypeLabels.attachmentOcr;
    case 'attachment_transcript':
      return context
          .t.chat.answerEvidence.sourceTypeLabels.attachmentTranscript;
    case 'attachment_text':
      return context.t.chat.answerEvidence.sourceTypeLabels.attachmentText;
    case 'attachment_summary':
      return context.t.chat.answerEvidence.sourceTypeLabels.attachmentSummary;
    case 'attachment_metadata':
      return context.t.chat.answerEvidence.sourceTypeLabels.attachmentMetadata;
    case 'attachment_excerpt':
      return context.t.chat.answerEvidence.sourceTypeLabels.attachmentExcerpt;
    default:
      return item.displaySourceTypeLabel;
  }
}

String _localizedScopeLabel(BuildContext context, String rawScope) {
  switch (rawScope.trim().toLowerCase()) {
    case 'this_thread':
      return context.t.chat.answerEvidence.scopeLabels.thisThread;
    default:
      return rawScope.trim();
  }
}

String _localizedConfidenceLabel(BuildContext context, String rawConfidence) {
  switch (rawConfidence.trim().toLowerCase()) {
    case 'high_relevance':
      return context.t.chat.answerEvidence.confidenceLabels.highRelevance;
    case 'relevant':
      return context.t.chat.answerEvidence.confidenceLabels.relevant;
    case 'possible_match':
      return context.t.chat.answerEvidence.confidenceLabels.possibleMatch;
    default:
      return rawConfidence.trim();
  }
}

String _localizedWhyUsed(BuildContext context, String rawWhyUsed) {
  final trimmed = rawWhyUsed.trim();
  if (trimmed.isEmpty) return trimmed;

  const legacyPrefix = 'Retrieved as relevant context for:';
  if (trimmed.startsWith(legacyPrefix)) {
    final query = trimmed.substring(legacyPrefix.length).trim();
    if (query.isNotEmpty) {
      return context.t.chat.answerEvidence.labels.whyUsedForQuery(query: query);
    }
  }

  if (!trimmed.contains(' ') &&
      !trimmed.contains('\n') &&
      trimmed.toLowerCase().startsWith('retrieved_as_')) {
    return trimmed;
  }

  if (trimmed.startsWith('The user asked') ||
      trimmed.startsWith('Used because it was relevant')) {
    return trimmed;
  }

  return context.t.chat.answerEvidence.labels.whyUsedForQuery(query: trimmed);
}
