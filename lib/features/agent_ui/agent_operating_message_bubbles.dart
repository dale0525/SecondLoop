part of 'agent_conversation_page.dart';

final class _OperatingUserBubble extends StatelessWidget {
  const _OperatingUserBubble({
    required this.content,
    required this.createdAtMs,
    required this.attachments,
  });

  final String content;
  final int? createdAtMs;
  final List<_AgentMessageAttachmentView> attachments;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AgentOperatingSystemTokens.surface,
                borderRadius:
                    BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
                border: Border.all(
                  color: AgentOperatingSystemTokens.outlineVariant,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      content,
                      style: AgentOperatingSystemTokens.bodyMd.copyWith(
                        color: AgentOperatingSystemTokens.onSurface,
                      ),
                    ),
                    if (attachments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _MessageAttachmentStrip(attachments: attachments),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (createdAtMs != null && createdAtMs! > 0) ...[
            const SizedBox(height: 4),
            _OperatingTurnTimeLabel(createdAtMs: createdAtMs!),
          ],
        ],
      ),
    );
  }
}

final class _OperatingAssistantBubble extends StatelessWidget {
  const _OperatingAssistantBubble({
    required this.content,
    required this.messageId,
    required this.createdAtMs,
    this.mediaResults = const <_AgentMessageMediaResultView>[],
  });

  final String content;
  final String messageId;
  final int? createdAtMs;
  final List<_AgentMessageMediaResultView> mediaResults;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AgentOperatingSystemTokens.surface,
                borderRadius:
                    BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
                border: Border.all(
                  color: AgentOperatingSystemTokens.outlineVariant,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      width: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AgentOperatingSystemTokens.secondary,
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(
                              AgentOperatingSystemTokens.radiusLg,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              content,
                              style: AgentOperatingSystemTokens.bodyMd.copyWith(
                                color: AgentOperatingSystemTokens.onSurface,
                              ),
                            ),
                            if (mediaResults.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              KeyedSubtree(
                                key: ValueKey(
                                  'agent_assistant_media_results_$messageId',
                                ),
                                child: _AssistantRuntimeMediaResults(
                                  results: mediaResults,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (createdAtMs != null && createdAtMs! > 0) ...[
            const SizedBox(height: 4),
            _OperatingTurnTimeLabel(createdAtMs: createdAtMs!),
          ],
        ],
      ),
    );
  }
}

final class _OperatingProcessingStrip extends StatelessWidget {
  const _OperatingProcessingStrip({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AgentOperatingSystemTokens.surfaceContainerLow,
          borderRadius:
              BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
          border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(
                Icons.settings_input_component_rounded,
                size: 14,
                color: AgentOperatingSystemTokens.secondary,
              ),
              for (var index = 0; index < labels.length; index++) ...[
                Text(
                  labels[index],
                  style: AgentOperatingSystemTokens.code.copyWith(
                    color: labels[index].toLowerCase().contains('vault')
                        ? AgentOperatingSystemTokens.secondary
                        : AgentOperatingSystemTokens.onSurfaceVariant,
                    fontWeight: labels[index].toLowerCase().contains('vault')
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
                if (index < labels.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Text(
                      '/',
                      style: TextStyle(
                        color: AgentOperatingSystemTokens.outlineVariant,
                        fontSize: 11,
                        height: 1,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
