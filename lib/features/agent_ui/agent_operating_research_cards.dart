part of 'agent_conversation_page.dart';

final class _OperatingAssistantResponse extends StatelessWidget {
  const _OperatingAssistantResponse({
    required this.message,
    required this.runtimeTurn,
    required this.contextSnapshot,
    required this.isFollowUpResearch,
    required this.mediaResults,
  });

  final Message message;
  final RuntimeConversationTurn? runtimeTurn;
  final RuntimeContextSnapshot? contextSnapshot;
  final bool isFollowUpResearch;
  final List<_AgentMessageMediaResultView> mediaResults;

  @override
  Widget build(BuildContext context) {
    final evidence = parseChatAnswerEvidence(message.citationsJson);
    final citationController = ChatAnswerCitationController(evidence);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AgentOperatingSystemTokens.secondary,
                width: 3,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _OperatingAssistantHeader(),
                if (isFollowUpResearch) ...[
                  const SizedBox(height: 10),
                  _OperatingContextUsedChip(snapshot: contextSnapshot),
                ],
                const SizedBox(height: 8),
                if (evidence != null)
                  _OperatingWebResearchCard(
                    message: message,
                    runtimeTurn: runtimeTurn,
                    evidence: evidence,
                    citationController: citationController,
                    followUp: isFollowUpResearch,
                  )
                else
                  _OperatingFallbackResearchCard(message: message),
                if (mediaResults.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  KeyedSubtree(
                    key: ValueKey(
                      'agent_assistant_media_results_${message.id}',
                    ),
                    child: _AssistantRuntimeMediaResults(results: mediaResults),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _OperatingAssistantHeader extends StatelessWidget {
  const _OperatingAssistantHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.smart_toy_outlined,
          size: 20,
          color: AgentOperatingSystemTokens.secondary,
        ),
        SizedBox(width: 8),
        Text(
          'SecondLoop Agent',
          style: TextStyle(
            color: AgentOperatingSystemTokens.secondary,
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

final class _OperatingContextUsedChip extends StatelessWidget {
  const _OperatingContextUsedChip({required this.snapshot});

  final RuntimeContextSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final packet = snapshot?.packet ?? const <String, Object?>{};
    final hasRecentTurns = _firstOperatingString([
          packet['recent_turns'],
          packet['recentTurns'],
        ]) !=
        null;
    final label = hasRecentTurns
        ? 'Context used: previous turn + recent_turns + web research'
        : 'Context used: previous turn + web research';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerLow,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.history_rounded,
              size: 13,
              color: AgentOperatingSystemTokens.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.code.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                  fontSize: 10,
                  height: 14 / 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingFallbackResearchCard extends StatelessWidget {
  const _OperatingFallbackResearchCard({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.content,
              style: AgentOperatingSystemTokens.bodyMd.copyWith(
                color: AgentOperatingSystemTokens.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingWebResearchCard extends StatelessWidget {
  const _OperatingWebResearchCard({
    required this.message,
    required this.runtimeTurn,
    required this.evidence,
    required this.citationController,
    required this.followUp,
  });

  final Message message;
  final RuntimeConversationTurn? runtimeTurn;
  final ChatAnswerEvidence evidence;
  final ChatAnswerCitationController citationController;
  final bool followUp;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surface,
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
        border: Border.all(color: AgentOperatingSystemTokens.outlineVariant),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!followUp) const _OperatingSearchResultHeader(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _OperatingMarkdownBody(
                messageId: message.id,
                text: message.content,
                citationController: citationController,
              ),
            ),
            if (!followUp)
              _OperatingVerifiedSourcesList(evidence: evidence)
            else
              _OperatingExtractedEvidenceSection(
                runtimeTurn: runtimeTurn,
                evidence: evidence,
              ),
            if (followUp)
              _OperatingResearchAuditFooter(
                message: message,
                runtimeTurn: runtimeTurn,
              )
            else
              const _OperatingResearchFooterChips(),
          ],
        ),
      ),
    );
  }
}

final class _OperatingSearchResultHeader extends StatelessWidget {
  const _OperatingSearchResultHeader();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'SEARCH RESULT',
                style: AgentOperatingSystemTokens.labelLg.copyWith(
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                  fontSize: 11,
                  height: 14 / 11,
                ),
              ),
            ),
            _OperatingStatusBadge(
              label: 'web_research',
              background:
                  AgentOperatingSystemTokens.secondary.withOpacity(0.10),
              foreground: AgentOperatingSystemTokens.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingMarkdownBody extends StatelessWidget {
  const _OperatingMarkdownBody({
    required this.messageId,
    required this.text,
    required this.citationController,
  });

  final String messageId;
  final String text;
  final ChatAnswerCitationController citationController;

  @override
  Widget build(BuildContext context) {
    return buildChatMarkdownPreviewBody(
      context,
      key: ValueKey('agent_operating_markdown_$messageId'),
      text: text,
      selectable: true,
      density: ChatMarkdownPreviewDensity.compact,
      bodyStyle: AgentOperatingSystemTokens.bodyMd.copyWith(
        color: AgentOperatingSystemTokens.onSurface,
      ),
      citationLabelResolver: citationController.chipLabelForHref,
      onTapRichLink: (href) async {
        final target = href.trim();
        if (target.isEmpty) return;
        final handledCitation = await citationController.handleCitationTap(
          context,
          href: target,
          onOpenDirectSource: (sourceHref) =>
              _openOperatingDirectSource(context, sourceHref),
        );
        if (handledCitation) return;
        await handleChatMarkdownTapLink(
          target,
          handleInApp: (_) async => false,
        );
      },
      onTapLink: (_, href, __) => unawaited(
        handleChatMarkdownTapLink(
          href,
          handleInApp: (_) async => false,
        ),
      ),
    );
  }
}

final class _OperatingVerifiedSourcesList extends StatelessWidget {
  const _OperatingVerifiedSourcesList({required this.evidence});

  final ChatAnswerEvidence evidence;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerLow.withOpacity(0.5),
        border: const Border(
          top: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'VERIFIED SOURCES',
              style: AgentOperatingSystemTokens.labelMd.copyWith(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontSize: 10,
                height: 14 / 10,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < evidence.directSources.length; i++) ...[
              _OperatingSourceRow(
                index: i + 1,
                source: evidence.directSources[i],
              ),
              if (i < evidence.directSources.length - 1)
                const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

final class _OperatingSourceRow extends StatelessWidget {
  const _OperatingSourceRow({
    required this.index,
    required this.source,
  });

  final int index;
  final ChatAnswerEvidenceDirectSource source;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AgentOperatingSystemTokens.surface,
      borderRadius: BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
      child: InkWell(
        key: ValueKey('agent_operating_source_$index'),
        borderRadius:
            BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
        onTap: () =>
            unawaited(_openOperatingDirectSource(context, source.href)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(AgentOperatingSystemTokens.radiusMd),
            border:
                Border.all(color: AgentOperatingSystemTokens.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  index.isOdd ? Icons.language_rounded : Icons.feed_outlined,
                  size: 18,
                  color: AgentOperatingSystemTokens.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        source.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AgentOperatingSystemTokens.labelLg.copyWith(
                          color: AgentOperatingSystemTokens.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _operatingSourceDomain(source),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgentOperatingSystemTokens.code.copyWith(
                          color: AgentOperatingSystemTokens.onSurfaceVariant,
                          fontSize: 10,
                          height: 13 / 10,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _operatingFetchedLabel(source.createdAtMs),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AgentOperatingSystemTokens.code.copyWith(
                          color: AgentOperatingSystemTokens.outline,
                          fontSize: 10,
                          height: 13 / 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AgentOperatingSystemTokens.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(
                      AgentOperatingSystemTokens.radiusSm,
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      '$index',
                      style: AgentOperatingSystemTokens.labelMd.copyWith(
                        color: AgentOperatingSystemTokens.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _OperatingExtractedEvidenceSection extends StatefulWidget {
  const _OperatingExtractedEvidenceSection({
    required this.runtimeTurn,
    required this.evidence,
  });

  final RuntimeConversationTurn? runtimeTurn;
  final ChatAnswerEvidence evidence;

  @override
  State<_OperatingExtractedEvidenceSection> createState() =>
      _OperatingExtractedEvidenceSectionState();
}

final class _OperatingExtractedEvidenceSectionState
    extends State<_OperatingExtractedEvidenceSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final evidenceText = _operatingExtractedEvidenceText(
      widget.runtimeTurn,
      widget.evidence,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color:
              AgentOperatingSystemTokens.surfaceContainerLow.withOpacity(0.55),
          child: InkWell(
            key: const ValueKey('agent_operating_extracted_evidence_toggle'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Extracted Evidence',
                      style: AgentOperatingSystemTokens.labelMd.copyWith(
                        color: AgentOperatingSystemTokens.onSurfaceVariant,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: AgentOperatingSystemTokens.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded)
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AgentOperatingSystemTokens.surface,
              border: Border(
                top: BorderSide(
                  color: AgentOperatingSystemTokens.outlineVariant,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AgentOperatingSystemTokens.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(
                    AgentOperatingSystemTokens.radiusSm,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    evidenceText,
                    style: AgentOperatingSystemTokens.code.copyWith(
                      color: AgentOperatingSystemTokens.onSurfaceVariant,
                      fontSize: 13,
                      height: 18 / 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

final class _OperatingResearchAuditFooter extends StatelessWidget {
  const _OperatingResearchAuditFooter({
    required this.message,
    required this.runtimeTurn,
  });

  final Message message;
  final RuntimeConversationTurn? runtimeTurn;

  @override
  Widget build(BuildContext context) {
    final trace = _operatingObjectMap(runtimeTurn?.raw['tool_trace']);
    final traceId = _firstOperatingString([
          trace['trace_id'],
          trace['traceId'],
          trace['id'],
          runtimeTurn?.raw['run_id'],
          runtimeTurn?.raw['turn_id'],
          message.id,
        ]) ??
        'not recorded';
    final snapshotId = _firstOperatingString([
          runtimeTurn?.raw['context_snapshot_id'],
          runtimeTurn?.raw['contextSnapshotId'],
          trace['context_snapshot_id'],
          trace['contextSnapshotId'],
        ]) ??
        'runtime context';
    final postprocess = _firstOperatingString([
          trace['postprocess'],
          trace['post_process'],
          trace['model_gateway'],
          trace['modelGateway'],
        ]) ??
        'skill_result_response';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AgentOperatingSystemTokens.surfaceContainerHigh.withOpacity(0.5),
        border: const Border(
          top: BorderSide(color: AgentOperatingSystemTokens.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Trace ID: $traceId | Snapshot: $snapshotId',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AgentOperatingSystemTokens.code.copyWith(
                  color: AgentOperatingSystemTokens.outline,
                  fontSize: 9,
                  height: 12 / 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _postprocessLabel(postprocess),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AgentOperatingSystemTokens.labelMd.copyWith(
                color: AgentOperatingSystemTokens.outline,
                fontSize: 9,
                height: 12 / 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _OperatingResearchFooterChips extends StatelessWidget {
  const _OperatingResearchFooterChips();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xFFE0E3E5),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              'citations required',
              style: TextStyle(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontSize: 10,
                height: 14 / 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            Text(
              'skill_result_response',
              style: TextStyle(
                color: AgentOperatingSystemTokens.onSurfaceVariant,
                fontSize: 10,
                height: 14 / 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _hasOperatingWebResearchState({
  required RuntimeAgentState? runtimeState,
  required List<Message> messages,
}) {
  for (final turn
      in runtimeState?.conversationTurns ?? const <RuntimeConversationTurn>[]) {
    if (_isOperatingWebResearchTurn(turn)) return true;
  }
  for (final message in messages) {
    if (_isOperatingWebResearchMessage(message, null)) return true;
  }
  return false;
}

bool _isOperatingWebResearchMessage(
  Message message,
  RuntimeConversationTurn? turn,
) {
  if (message.role != 'assistant') return false;
  final evidence = parseChatAnswerEvidence(message.citationsJson);
  if (evidence?.directSources.any(_isOperatingWebResearchSource) ?? false) {
    return true;
  }
  return turn != null && _isOperatingWebResearchTurn(turn);
}

bool _isOperatingWebResearchTurn(RuntimeConversationTurn turn) {
  if (turn.role != 'assistant') return false;
  final evidence = parseChatAnswerEvidence(turn.citationsJson);
  if (evidence?.directSources.any(_isOperatingWebResearchSource) ?? false) {
    return true;
  }
  final drafts = _operatingObjectList(turn.raw['web_research_drafts']);
  if (drafts.isNotEmpty) return true;
  final trace = _operatingObjectMap(turn.raw['tool_trace']);
  final skill = _firstOperatingString([
    trace['skill'],
    trace['skill_id'],
    trace['skillId'],
    trace['tool'],
  ]);
  return skill == 'web-research' || skill == 'web_research';
}

bool _isOperatingWebResearchSource(ChatAnswerEvidenceDirectSource source) {
  final type = source.sourceType.trim().toLowerCase();
  final label = (source.sourceTypeLabel ?? '').trim().toLowerCase();
  final scope = (source.scopeLabel ?? '').trim().toLowerCase();
  return type == 'web_research' ||
      type == 'runtime_web_research' ||
      label.contains('web research') ||
      scope.contains('web research');
}

Future<bool> _openOperatingDirectSource(
  BuildContext context,
  String href,
) async {
  final target = href.trim();
  if (target.isEmpty) return false;
  final uri = Uri.tryParse(target);
  if (uri == null) return false;
  if (uri.scheme.toLowerCase() == 'secondloop') {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          context.t.errors.loadFailed(error: 'unsupported_secondloop_link'),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
    return false;
  }
  await handleChatMarkdownTapLink(
    target,
    handleInApp: (_) async => false,
  );
  return true;
}

Map<String, Object?> _operatingObjectMap(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  return raw.map((key, value) => MapEntry('$key', value as Object?));
}

List<Map<String, Object?>> _operatingObjectList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return raw
      .whereType<Map>()
      .map((item) =>
          item.map((key, value) => MapEntry('$key', value as Object?)))
      .toList(growable: false);
}

String _operatingSourceDomain(ChatAnswerEvidenceDirectSource source) {
  final uri = Uri.tryParse(source.href);
  final host = uri?.host.trim() ?? '';
  if (host.isNotEmpty) return host;
  final label = source.label.trim();
  if (label.isNotEmpty) return label;
  return source.href;
}

String _operatingFetchedLabel(int? ms) {
  if (ms == null || ms <= 0) return 'Retrieved: runtime source';
  final date = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String two(int value) => value.toString().padLeft(2, '0');
  return 'Retrieved: ${months[date.month - 1]} ${date.day}, '
      '${date.year}, ${two(date.hour)}:${two(date.minute)} UTC';
}

String _operatingExtractedEvidenceText(
  RuntimeConversationTurn? turn,
  ChatAnswerEvidence evidence,
) {
  final trace = _operatingObjectMap(turn?.raw['tool_trace']);
  final direct = _firstOperatingString([
    turn?.raw['extracted_evidence'],
    turn?.raw['extractedEvidence'],
    turn?.raw['evidence'],
    trace['extracted_evidence'],
    trace['extractedEvidence'],
    trace['match'],
  ]);
  if (direct != null) return direct;
  for (final source in evidence.directSources) {
    final highlight = source.highlightedText?.trim();
    if (highlight != null && highlight.isNotEmpty) return highlight;
    final snippet = source.snippet.trim();
    if (snippet.isNotEmpty) return snippet;
  }
  return 'Evidence is available in the cited web-research sources.';
}

String _postprocessLabel(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return 'Model Gateway: Post-processed';
  if (normalized == 'skill_result_response') {
    return 'Model Gateway: Post-processed';
  }
  return normalized;
}
