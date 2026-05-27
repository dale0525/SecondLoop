part of 'agent_conversation_page.dart';

final class _AssistantRuntimeMediaResults extends StatelessWidget {
  const _AssistantRuntimeMediaResults({required this.results});

  final List<_AgentMessageMediaResultView> results;

  @override
  Widget build(BuildContext context) {
    final labels = _runtimeMediaInlineLabels(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < results.length; index++) ...[
          _AssistantRuntimeMediaResult(
            result: results[index],
            labels: labels,
          ),
          if (index < results.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AgentDesignTokens.gapMd),
              child: Divider(height: 1),
            ),
        ],
      ],
    );
  }
}

final class _AssistantRuntimeMediaResult extends StatelessWidget {
  const _AssistantRuntimeMediaResult({
    required this.result,
    required this.labels,
  });

  final _AgentMessageMediaResultView result;
  final _RuntimeMediaInlineLabels labels;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              result.isAudioResult
                  ? Icons.graphic_eq_rounded
                  : Icons.analytics_outlined,
              size: 18,
            ),
            const SizedBox(width: AgentDesignTokens.gapSm),
            Flexible(
              child: Text(
                result.isAudioResult ? 'Meeting Audio Result' : 'Media Result',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
        if (result.title.trim().isNotEmpty) ...[
          const SizedBox(height: AgentDesignTokens.gapSm),
          Text(
            result.title,
            style: AgentOperatingSystemTokens.labelLg.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        if (result.ocrText != null)
          _RuntimeMediaResultTextSection(
            title: 'OCR TEXT',
            body: result.ocrText!,
            labelStyle: labelStyle,
            highlighted: true,
          ),
        if (result.transcript != null)
          _RuntimeMediaResultTextSection(
            title: labels.transcript,
            body: result.transcript!,
            labelStyle: labelStyle,
          ),
        if (result.summary != null)
          _RuntimeMediaResultTextSection(
            title: _runtimeMediaSummaryLabel(
              result.mediaType,
              labels: labels,
              ocr: result.isOcrResult,
            ),
            body: result.summary!,
            labelStyle: labelStyle,
          ),
        if (_runtimeMediaMetadataRows(result).isNotEmpty)
          _RuntimeMediaResultMetadataRows(
            rows: _runtimeMediaMetadataRows(result),
            labelStyle: labelStyle,
          ),
        if (result.decisions.isNotEmpty)
          _RuntimeMediaResultListSection(
            title: labels.decisions,
            items: result.decisions,
            labelStyle: labelStyle,
            listItem: labels.listItem,
          ),
        if (result.actionItems.isNotEmpty)
          _RuntimeMediaResultListSection(
            title: labels.actionItems,
            items: result.actionItems,
            labelStyle: labelStyle,
            listItem: labels.listItem,
          ),
        if (result.sources.isNotEmpty)
          _RuntimeMediaResultListSection(
            title: labels.sources,
            items: result.sources,
            labelStyle: labelStyle,
            listItem: labels.listItem,
            compact: true,
          ),
      ],
    );
  }
}

final class _RuntimeMediaResultTextSection extends StatelessWidget {
  const _RuntimeMediaResultTextSection({
    required this.title,
    required this.body,
    required this.labelStyle,
    this.highlighted = false,
  });

  final String title;
  final String body;
  final TextStyle? labelStyle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return Padding(
      padding: const EdgeInsets.only(top: AgentDesignTokens.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: labelStyle),
          const SizedBox(height: AgentDesignTokens.gapXs),
          DecoratedBox(
            decoration: highlighted
                ? BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(
                      AgentOperatingSystemTokens.radiusSm,
                    ),
                    border: Border.all(
                      color: colors.outlineVariant,
                    ),
                  )
                : const BoxDecoration(),
            child: Padding(
              padding: highlighted
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                  : EdgeInsets.zero,
              child: Text(
                body,
                style: TextStyle(
                  color: highlighted ? colors.secondary : colors.onSurface,
                  fontFamily: highlighted ? 'monospace' : null,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _RuntimeMediaResultMetadataRows extends StatelessWidget {
  const _RuntimeMediaResultMetadataRows({
    required this.rows,
    required this.labelStyle,
  });

  final List<(String, String)> rows;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return Padding(
      padding: const EdgeInsets.only(top: AgentDesignTokens.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < rows.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == rows.length - 1 ? 0 : AgentDesignTokens.gapXs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(rows[index].$1, style: labelStyle),
                  ),
                  Expanded(
                    child: Text(
                      rows[index].$2,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

List<(String, String)> _runtimeMediaMetadataRows(
  _AgentMessageMediaResultView result,
) {
  final rows = <(String, String)>[];
  if (result.meetingId?.trim().isNotEmpty ?? false) {
    rows.add(('Meeting ID:', result.meetingId!.trim()));
  }
  if (result.durationLabel?.trim().isNotEmpty ?? false) {
    rows.add(('Duration:', result.durationLabel!.trim()));
  }
  if (result.sourceId?.trim().isNotEmpty ?? false) {
    rows.add(('Source ID:', result.sourceId!.trim()));
  }
  if (result.confidenceLabel?.trim().isNotEmpty ?? false) {
    rows.add(('Confidence:', result.confidenceLabel!.trim()));
  }
  final savedLabel = result.savedToVaultLabel?.trim();
  if (savedLabel != null && savedLabel.isNotEmpty) {
    rows.add(('Saved to Vault:', savedLabel));
  } else if (result.isOcrResult) {
    rows.add(('Saved to Vault:', 'Not reported'));
  }
  return rows;
}

final class _RuntimeMediaResultListSection extends StatelessWidget {
  const _RuntimeMediaResultListSection({
    required this.title,
    required this.items,
    required this.labelStyle,
    required this.listItem,
    this.compact = false,
  });

  final String title;
  final List<String> items;
  final TextStyle? labelStyle;
  final String Function(String value) listItem;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.agentOs;
    return Padding(
      padding: const EdgeInsets.only(top: AgentDesignTokens.gapMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: labelStyle),
          const SizedBox(height: AgentDesignTokens.gapXs),
          for (final item in items)
            Padding(
              padding: EdgeInsets.only(
                bottom: compact ? 0 : AgentDesignTokens.gapXs,
              ),
              child: Text(
                compact ? item : listItem(item),
                style: TextStyle(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _runtimeMediaSummaryLabel(
  String mediaType, {
  required _RuntimeMediaInlineLabels labels,
  required bool ocr,
}) {
  if (ocr) return 'SUMMARY';
  final normalized = mediaType.trim().toLowerCase();
  return normalized == 'audio' ? labels.meetingMinutes : labels.summary;
}
