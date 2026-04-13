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
  Future<void> Function(String documentId)? onOpenMemoryCard,
  bool Function(String documentId)? canOpenMemoryCard,
  bool Function(String href)? canOpenDirectSource,
  Future<ChatAnswerEvidenceMemoryCard?> Function(
    ChatAnswerEvidenceMemoryCard card,
    String title,
    String summary,
  )? onCorrectMemoryCard,
  bool Function(String documentId)? canCorrectMemoryCard,
  Future<ChatAnswerEvidenceMemoryCard?> Function(
    ChatAnswerEvidenceMemoryCard card,
  )? onRefreshMemoryCard,
  Future<void> Function(String documentId)? onDisableMemoryCard,
  bool Function(String documentId)? canDisableMemoryCard,
  Future<void> Function(String documentId)? onDeleteMemoryCard,
  bool Function(String documentId)? canDeleteMemoryCard,
}) {
  final isWide = MediaQuery.sizeOf(context).width >= 960;
  final child = ChatAnswerEvidencePanel(
    evidence: evidence,
    initialTab: initialTab,
    highlightedHref: highlightedHref,
    onOpenDirectSource: onOpenDirectSource,
    onOpenMemoryCard: onOpenMemoryCard,
    canOpenMemoryCard: canOpenMemoryCard,
    canOpenDirectSource: canOpenDirectSource,
    onCorrectMemoryCard: onCorrectMemoryCard,
    canCorrectMemoryCard: canCorrectMemoryCard,
    onRefreshMemoryCard: onRefreshMemoryCard,
    onDisableMemoryCard: onDisableMemoryCard,
    canDisableMemoryCard: canDisableMemoryCard,
    onDeleteMemoryCard: onDeleteMemoryCard,
    canDeleteMemoryCard: canDeleteMemoryCard,
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
    this.onOpenMemoryCard,
    this.canOpenMemoryCard,
    this.canOpenDirectSource,
    this.onCorrectMemoryCard,
    this.canCorrectMemoryCard,
    this.onRefreshMemoryCard,
    this.onDisableMemoryCard,
    this.canDisableMemoryCard,
    this.onDeleteMemoryCard,
    this.canDeleteMemoryCard,
    this.highlightedHref,
    super.key,
  });

  final ChatAnswerEvidence evidence;
  final ChatAnswerEvidenceTab initialTab;
  final String? highlightedHref;
  final Future<void> Function(String href) onOpenDirectSource;
  final Future<void> Function(String documentId)? onOpenMemoryCard;
  final bool Function(String documentId)? canOpenMemoryCard;
  final bool Function(String href)? canOpenDirectSource;
  final Future<ChatAnswerEvidenceMemoryCard?> Function(
    ChatAnswerEvidenceMemoryCard card,
    String title,
    String summary,
  )? onCorrectMemoryCard;
  final bool Function(String documentId)? canCorrectMemoryCard;
  final Future<ChatAnswerEvidenceMemoryCard?> Function(
    ChatAnswerEvidenceMemoryCard card,
  )? onRefreshMemoryCard;
  final Future<void> Function(String documentId)? onDisableMemoryCard;
  final bool Function(String documentId)? canDisableMemoryCard;
  final Future<void> Function(String documentId)? onDeleteMemoryCard;
  final bool Function(String documentId)? canDeleteMemoryCard;

  @override
  State<ChatAnswerEvidencePanel> createState() =>
      _ChatAnswerEvidencePanelState();
}

class _ChatAnswerEvidencePanelState extends State<ChatAnswerEvidencePanel> {
  late List<ChatAnswerEvidenceMemoryCard> _memoryCards;
  int _refreshEpoch = 0;

  @override
  void initState() {
    super.initState();
    _memoryCards = List<ChatAnswerEvidenceMemoryCard>.from(
      widget.evidence.memoryCards,
    );
    _refreshMemoryCards();
  }

  @override
  void didUpdateWidget(covariant ChatAnswerEvidencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
        oldWidget.evidence.memoryCards, widget.evidence.memoryCards)) {
      _memoryCards = List<ChatAnswerEvidenceMemoryCard>.from(
        widget.evidence.memoryCards,
      );
      _refreshMemoryCards();
    }
  }

  Future<void> _refreshMemoryCards() async {
    final refresh = widget.onRefreshMemoryCard;
    if (refresh == null || _memoryCards.isEmpty) return;
    final refreshEpoch = ++_refreshEpoch;
    final cardsToRefresh =
        List<ChatAnswerEvidenceMemoryCard>.from(_memoryCards);
    final refreshed = await Future.wait(
      cardsToRefresh.map((card) async {
        try {
          final updated = await refresh(card);
          if (refreshEpoch != _refreshEpoch) return card;
          return updated ?? card;
        } catch (_) {
          if (refreshEpoch != _refreshEpoch) return card;
          return card;
        }
      }),
    );
    if (!mounted || refreshEpoch != _refreshEpoch) return;
    setState(() {
      _memoryCards = refreshed;
    });
  }

  void _invalidatePendingRefreshes() {
    _refreshEpoch += 1;
  }

  void _showActionError(Object error) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.t.errors.loadFailed(error: '$error')),
        duration: const Duration(seconds: 3),
      ),
    );
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
                    canOpenDirectSource: widget.canOpenDirectSource,
                    onOpenDirectSource: widget.onOpenDirectSource,
                  ),
                ChatAnswerEvidenceTab.memoryCards => ListView.separated(
                    key: const ValueKey('answer_evidence_memory_cards'),
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final item = _memoryCards[index];
                      final whyUsed = item.whyUsed?.trim() ?? '';
                      final isDisabled = !item.useForAskAi;
                      final isDeleted = item.isDeleted;
                      final isKnowledgePage =
                          item.documentId.startsWith('page:');
                      final canOpenMemoryCard = widget.onOpenMemoryCard !=
                              null &&
                          (widget.canOpenMemoryCard?.call(item.documentId) ??
                              true);
                      final canCorrectMemoryCard = widget.onCorrectMemoryCard !=
                              null &&
                          (widget.canCorrectMemoryCard?.call(item.documentId) ??
                              true);
                      final canDisableMemoryCard = widget.onDisableMemoryCard !=
                              null &&
                          (widget.canDisableMemoryCard?.call(item.documentId) ??
                              true);
                      final canDeleteMemoryCard = widget.onDeleteMemoryCard !=
                              null &&
                          (widget.canDeleteMemoryCard?.call(item.documentId) ??
                              true);
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
                                if (canOpenMemoryCard)
                                  TextButton(
                                    onPressed: () => widget.onOpenMemoryCard!(
                                      item.documentId,
                                    ),
                                    child: Text(
                                      context.t.chat.answerEvidence.actions
                                          .inspectMemory,
                                    ),
                                  ),
                                if (canOpenMemoryCard && canCorrectMemoryCard)
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
                                      ChatAnswerEvidenceMemoryCard? updated;
                                      try {
                                        updated =
                                            await widget.onCorrectMemoryCard!(
                                          item,
                                          draft.title,
                                          draft.summary,
                                        );
                                      } catch (error) {
                                        if (!mounted) return;
                                        _showActionError(error);
                                        return;
                                      }
                                      if (!mounted || updated == null) return;
                                      final updatedCard = updated;
                                      _invalidatePendingRefreshes();
                                      setState(() {
                                        _memoryCards[index] = updatedCard;
                                      });
                                    },
                                    child: Text(
                                      context.t.chat.answerEvidence.actions
                                          .correct,
                                    ),
                                  ),
                                if (canOpenMemoryCard &&
                                    canDisableMemoryCard &&
                                    !isDeleted)
                                  TextButton(
                                    onPressed: isDisabled
                                        ? null
                                        : () async {
                                            try {
                                              await widget.onDisableMemoryCard!(
                                                item.documentId,
                                              );
                                            } catch (error) {
                                              if (!mounted) return;
                                              _showActionError(error);
                                              return;
                                            }
                                            if (!mounted) return;
                                            _invalidatePendingRefreshes();
                                            setState(() {
                                              _memoryCards[index] =
                                                  item.copyWith(
                                                useForAskAi: false,
                                              );
                                            });
                                          },
                                    child: Text(
                                      context.t.chat.answerEvidence.actions
                                          .dontUse,
                                    ),
                                  ),
                                if (canOpenMemoryCard && canDeleteMemoryCard)
                                  TextButton(
                                    onPressed: isDeleted
                                        ? null
                                        : () async {
                                            try {
                                              await widget.onDeleteMemoryCard!(
                                                item.documentId,
                                              );
                                            } catch (error) {
                                              if (!mounted) return;
                                              _showActionError(error);
                                              return;
                                            }
                                            if (!mounted) return;
                                            _invalidatePendingRefreshes();
                                            setState(() {
                                              _memoryCards[index] =
                                                  item.copyWith(
                                                isDeleted: true,
                                              );
                                            });
                                          },
                                    child: Text(
                                      isKnowledgePage
                                          ? context.t.memory.actions
                                              .permanentlyRemove
                                          : context.t.chat.answerEvidence
                                              .actions.deleteMemory,
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
    this.canOpenDirectSource,
  });

  final ChatAnswerEvidence evidence;
  final String? highlightedHref;
  final Future<void> Function(String href) onOpenDirectSource;
  final bool Function(String href)? canOpenDirectSource;

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
        final canOpen = canOpenDirectSource?.call(item.href) ?? true;
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
                  onPressed:
                      canOpen ? () => onOpenDirectSource(item.href) : null,
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
