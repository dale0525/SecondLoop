import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'chat_answer_evidence_models.dart';
import 'chat_answer_evidence_sheet.dart';

class ChatAnswerCitationController {
  const ChatAnswerCitationController(this.evidence);

  final ChatAnswerEvidence? evidence;

  bool get hasEvidence => evidence?.hasEvidence ?? false;

  bool handlesHref(String href) =>
      evidence?.hasDirectSourceForHref(href) ?? false;

  String? chipLabelForHref(String href) => evidence?.chipLabelForHref(href);

  Future<bool> handleCitationTap(
    BuildContext context, {
    required String href,
    required Future<void> Function(String href) onOpenDirectSource,
    Future<void> Function(String documentId)? onOpenMemoryCard,
    Future<ChatAnswerEvidenceMemoryCard?> Function(
      ChatAnswerEvidenceMemoryCard card,
      String title,
      String summary,
    )? onCorrectMemoryCard,
    Future<ChatAnswerEvidenceMemoryCard?> Function(
      ChatAnswerEvidenceMemoryCard card,
    )? onRefreshMemoryCard,
    Future<void> Function(String documentId)? onDisableMemoryCard,
    Future<void> Function(String documentId)? onDeleteMemoryCard,
  }) async {
    if (!handlesHref(href) || evidence == null) {
      return false;
    }
    await showChatAnswerEvidenceSheet(
      context,
      evidence: evidence!,
      highlightedHref: href,
      onOpenDirectSource: onOpenDirectSource,
      onOpenMemoryCard: onOpenMemoryCard,
      onCorrectMemoryCard: onCorrectMemoryCard,
      onRefreshMemoryCard: onRefreshMemoryCard,
      onDisableMemoryCard: onDisableMemoryCard,
      onDeleteMemoryCard: onDeleteMemoryCard,
    );
    return true;
  }

  Future<void> openEvidence(
    BuildContext context, {
    ChatAnswerEvidenceTab initialTab = ChatAnswerEvidenceTab.directSources,
    String? highlightedHref,
    required Future<void> Function(String href) onOpenDirectSource,
    Future<void> Function(String documentId)? onOpenMemoryCard,
    bool Function(String href)? canOpenDirectSource,
    Future<ChatAnswerEvidenceMemoryCard?> Function(
      ChatAnswerEvidenceMemoryCard card,
      String title,
      String summary,
    )? onCorrectMemoryCard,
    Future<ChatAnswerEvidenceMemoryCard?> Function(
      ChatAnswerEvidenceMemoryCard card,
    )? onRefreshMemoryCard,
    Future<void> Function(String documentId)? onDisableMemoryCard,
    Future<void> Function(String documentId)? onDeleteMemoryCard,
  }) async {
    final current = evidence;
    if (current == null || !current.hasEvidence) return;
    await showChatAnswerEvidenceSheet(
      context,
      evidence: current,
      initialTab: initialTab,
      highlightedHref: highlightedHref,
      onOpenDirectSource: onOpenDirectSource,
      onOpenMemoryCard: onOpenMemoryCard,
      canOpenDirectSource: canOpenDirectSource,
      onCorrectMemoryCard: onCorrectMemoryCard,
      onRefreshMemoryCard: onRefreshMemoryCard,
      onDisableMemoryCard: onDisableMemoryCard,
      onDeleteMemoryCard: onDeleteMemoryCard,
    );
  }
}

class ChatAnswerEvidenceSummaryBar extends StatelessWidget {
  const ChatAnswerEvidenceSummaryBar({
    required this.evidence,
    required this.onOpenSources,
    required this.onOpenMemory,
    required this.onOpenEvidence,
    super.key,
  });

  final ChatAnswerEvidence evidence;
  final VoidCallback onOpenSources;
  final VoidCallback onOpenMemory;
  final VoidCallback onOpenEvidence;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (evidence.directSources.isNotEmpty)
          _SummaryActionChip(
            label: context.t.chat.answerEvidence.summary.sourcesUsed(
              count: evidence.directSources.length,
            ),
            onPressed: onOpenSources,
          ),
        if (evidence.memoryCards.isNotEmpty)
          _SummaryActionChip(
            label: context.t.chat.answerEvidence.summary.memoryCardsUsed(
              count: evidence.memoryCards.length,
            ),
            onPressed: onOpenMemory,
          ),
        _SummaryActionChip(
          label: context.t.chat.answerEvidence.summary.openEvidence,
          onPressed: onOpenEvidence,
          emphasized: true,
        ),
      ],
    );
  }
}

class _SummaryActionChip extends StatelessWidget {
  const _SummaryActionChip({
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onPressed,
      side: BorderSide(
        color: emphasized
            ? Theme.of(context).colorScheme.primary.withOpacity(0.28)
            : Theme.of(context).colorScheme.outlineVariant,
      ),
      backgroundColor: emphasized
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.65)
          : Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withOpacity(0.6),
    );
  }
}
