import 'package:flutter/material.dart';

import '../../ui/sl_button.dart';
import '../actions/suggestions_parser.dart';
import 'chat_answer_citation_controller.dart';
import 'chat_answer_evidence_models.dart';

class ChatAssistantMessageFooter extends StatelessWidget {
  const ChatAssistantMessageFooter({
    required this.evidence,
    required this.onOpenSources,
    required this.actionSuggestions,
    required this.onTapActionSuggestion,
    super.key,
  });

  final ChatAnswerEvidence? evidence;
  final VoidCallback onOpenSources;
  final List<ActionSuggestion> actionSuggestions;
  final void Function(ActionSuggestion suggestion, int index)
      onTapActionSuggestion;

  @override
  Widget build(BuildContext context) {
    final currentEvidence = evidence;
    final hasEvidence = currentEvidence != null && currentEvidence.hasEvidence;
    if (!hasEvidence && actionSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasEvidence)
          Padding(
            key: const ValueKey('assistant_message_footer_evidence'),
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ChatAnswerEvidenceSummaryBar(
                evidence: currentEvidence,
                onOpenSources: onOpenSources,
              ),
            ),
          ),
        if (actionSuggestions.isNotEmpty)
          Padding(
            key: const ValueKey('assistant_message_footer_suggestions'),
            padding: EdgeInsets.only(top: hasEvidence ? 10 : 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < actionSuggestions.length; i += 1)
                    SlButton(
                      variant: SlButtonVariant.outline,
                      onPressed: () =>
                          onTapActionSuggestion(actionSuggestions[i], i),
                      icon: Icon(
                        actionSuggestions[i].type == 'event'
                            ? Icons.event_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      child: Text(
                        actionSuggestions[i].whenText?.trim().isNotEmpty == true
                            ? '${actionSuggestions[i].title} (${actionSuggestions[i].whenText})'
                            : actionSuggestions[i].title,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
