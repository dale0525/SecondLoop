import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
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
    canOpenDirectSource: canOpenDirectSource,
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

class ChatAnswerEvidencePanel extends StatelessWidget {
  const ChatAnswerEvidencePanel({
    required this.evidence,
    required this.initialTab,
    required this.onOpenDirectSource,
    this.canOpenDirectSource,
    this.highlightedHref,
    this.onOpenMemoryCard,
    this.canOpenMemoryCard,
    this.onCorrectMemoryCard,
    this.canCorrectMemoryCard,
    this.onRefreshMemoryCard,
    this.onDisableMemoryCard,
    this.canDisableMemoryCard,
    this.onDeleteMemoryCard,
    this.canDeleteMemoryCard,
    super.key,
  });

  final ChatAnswerEvidence evidence;
  final ChatAnswerEvidenceTab initialTab;
  final String? highlightedHref;
  final Future<void> Function(String href) onOpenDirectSource;
  final bool Function(String href)? canOpenDirectSource;
  final Future<void> Function(String documentId)? onOpenMemoryCard;
  final bool Function(String documentId)? canOpenMemoryCard;
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(context.t.chat.answerEvidence.title),
      ),
      body: _DirectSourceList(
        evidence: evidence,
        highlightedHref: highlightedHref,
        onOpenDirectSource: onOpenDirectSource,
        canOpenDirectSource: canOpenDirectSource,
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
        final isMessage = item.sourceType.trim().toLowerCase() == 'message';
        final canOpen =
            !isMessage && (canOpenDirectSource?.call(item.href) ?? true);
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
                  _MetaPill(label: '[${index + 1}]'),
                  _MetaPill(label: _localizedSourceTypeLabel(context, item)),
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
                  if (isMessage)
                    _MetaPill(
                      label: _messageTimestampLabel(context, item.createdAtMs),
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
              if (canOpen) ...[
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

String _localizedSourceTypeLabel(
  BuildContext context,
  ChatAnswerEvidenceDirectSource item,
) {
  switch (item.sourceTypeLabel?.trim().toLowerCase()) {
    case 'item':
      return context.t.chat.answerEvidence.sourceTypeLabels.item;
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

String _messageTimestampLabel(BuildContext context, int? createdAtMs) {
  if (createdAtMs == null || createdAtMs <= 0) {
    return context.t.chat.answerEvidence.sourceTypeLabels.chatMessage;
  }

  final dateTime = DateTime.fromMillisecondsSinceEpoch(createdAtMs).toLocal();
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatShortDate(dateTime);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(dateTime));
  return '$date $time';
}
