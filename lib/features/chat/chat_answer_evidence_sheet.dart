import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import 'chat_answer_evidence_models.dart';

Future<void> showChatAnswerEvidenceSheet(
  BuildContext context, {
  required ChatAnswerEvidence evidence,
  String? highlightedHref,
  required Future<bool> Function(String href) onOpenDirectSource,
  bool Function(String href)? canOpenDirectSource,
}) {
  final isWide = MediaQuery.sizeOf(context).width >= 960;
  final child = ChatAnswerEvidencePanel(
    evidence: evidence,
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
    required this.onOpenDirectSource,
    this.canOpenDirectSource,
    this.highlightedHref,
    super.key,
  });

  final ChatAnswerEvidence evidence;
  final String? highlightedHref;
  final Future<bool> Function(String href) onOpenDirectSource;
  final bool Function(String href)? canOpenDirectSource;

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
  final Future<bool> Function(String href) onOpenDirectSource;
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
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      final loadFailed = context.t.errors.loadFailed;
                      final unsupportedMessage = loadFailed(
                        error: 'unsupported_secondloop_link',
                      );
                      try {
                        final opened = await onOpenDirectSource(item.href);
                        if (opened) return;
                        messenger?.showSnackBar(
                          SnackBar(
                            content: Text(unsupportedMessage),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      } catch (error) {
                        final errorMessage = loadFailed(error: '$error');
                        messenger?.showSnackBar(
                          SnackBar(
                            content: Text(errorMessage),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
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
  for (final rawLabel in [item.sourceTypeLabel, item.sourceType]) {
    final localized = _localizedSourceTypeLabelValue(context, rawLabel);
    if (localized != null) return localized;
  }
  return item.displaySourceTypeLabel;
}

String? _localizedSourceTypeLabelValue(BuildContext context, String? rawLabel) {
  switch (_serverLabelKey(rawLabel)) {
    case 'item':
    case 'todo':
      return context.t.chat.answerEvidence.sourceTypeLabels.item;
    case 'chat_message':
    case 'message':
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
    case 'conversation':
    case 'conversation_turn':
      return context.t.chat.answerEvidence.sourceTypeLabels.conversation;
    case 'document':
      return context.t.chat.answerEvidence.sourceTypeLabels.document;
    case 'transcript':
      return context.t.chat.answerEvidence.sourceTypeLabels.transcript;
    case 'summary':
      return context.t.chat.answerEvidence.sourceTypeLabels.summary;
    case 'working_set':
    case 'working_set_fragment':
      return context.t.chat.answerEvidence.sourceTypeLabels.workingSetFragment;
    case 'runtime_context':
      return context.t.chat.answerEvidence.sourceTypeLabels.runtimeContext;
    case 'web_research':
      return context.t.chat.answerEvidence.sourceTypeLabels.webResearch;
    default:
      return null;
  }
}

String _localizedScopeLabel(BuildContext context, String rawScope) {
  switch (_serverLabelKey(rawScope)) {
    case 'this_thread':
      return context.t.chat.answerEvidence.scopeLabels.thisThread;
    case 'runtime_retrieval':
      return context.t.chat.answerEvidence.scopeLabels.runtimeRetrieval;
    case 'runtime_web_research':
      return context.t.chat.answerEvidence.scopeLabels.runtimeWebResearch;
    default:
      return rawScope.trim();
  }
}

String _localizedConfidenceLabel(BuildContext context, String rawConfidence) {
  switch (_serverLabelKey(rawConfidence)) {
    case 'high_relevance':
      return context.t.chat.answerEvidence.confidenceLabels.highRelevance;
    case 'relevant':
      return context.t.chat.answerEvidence.confidenceLabels.relevant;
    case 'possible_match':
      return context.t.chat.answerEvidence.confidenceLabels.possibleMatch;
    case 'cited_source':
      return context.t.chat.answerEvidence.confidenceLabels.citedSource;
    default:
      return rawConfidence.trim();
  }
}

String _serverLabelKey(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return '';
  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
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
