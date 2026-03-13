import 'package:flutter/material.dart';

import '../../core/backend/knowledge_index_models.dart';
import '../../i18n/strings.g.dart';
import '../../ui/sl_surface.dart';
import 'knowledge_index_settings_card.dart';

class KnowledgeIndexStatusCard extends StatelessWidget {
  const KnowledgeIndexStatusCard({super.key, this.debugStats});

  final KnowledgeDebugStats? debugStats;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const KnowledgeIndexSettingsCard(),
        if (debugStats case final stats?) ...[
          const SizedBox(height: 12),
          _KnowledgeMemoryStatsCard(stats: stats),
        ],
      ],
    );
  }
}

final class _KnowledgeMemoryStatsCard extends StatelessWidget {
  const _KnowledgeMemoryStatsCard({required this.stats});

  final KnowledgeDebugStats stats;

  String? _formatTimestamp(int? value) {
    if (value == null || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: false)
        .toLocal()
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      context.t.settings.knowledgeIndex.debug.chips.total(
        count: stats.totalDocuments,
      ),
      context.t.settings.knowledgeIndex.debug.chips.generated(
        count: stats.generatedDocuments,
      ),
      context.t.settings.knowledgeIndex.debug.chips.source(
        count: stats.sourceDocuments,
      ),
      context.t.settings.knowledgeIndex.debug.chips.summaries(
        count: stats.summaryDocuments,
      ),
      context.t.settings.knowledgeIndex.debug.chips.preferences(
        count: stats.preferenceDocuments,
      ),
      context.t.settings.knowledgeIndex.debug.chips.profiles(
        count: stats.profileDocuments,
      ),
      context.t.settings.knowledgeIndex.debug.chips.events(
        count: stats.eventDocuments,
      ),
      context.t.settings.knowledgeIndex.debug.chips.patterns(
        count: stats.patternDocuments,
      ),
      context.t.settings.knowledgeIndex.debug.chips.usageRows(
        count: stats.usageStatDocuments,
      ),
    ];
    final onLabel = context.t.settings.knowledgeIndex.debug.detail.on;
    final offLabel = context.t.settings.knowledgeIndex.debug.detail.off;
    final detailLines = <String>[
      context.t.settings.knowledgeIndex.debug.detail.generatedMemoryRetrieval(
        value: stats.generatedMemoryRetrievalEnabled ? onLabel : offLabel,
      ),
      context.t.settings.knowledgeIndex.debug.detail.hotnessRerank(
        value: stats.hotnessRerankEnabled ? onLabel : offLabel,
      ),
      context.t.settings.knowledgeIndex.debug.detail.sessionDigest(
        value: stats.sessionDigestEnabled ? onLabel : offLabel,
      ),
      if (_formatTimestamp(stats.lastSynthesisAtMs) case final value?)
        context.t.settings.knowledgeIndex.debug.detail
            .lastSynthesis(value: value),
      if (_formatTimestamp(stats.lastRetrievedAtMs) case final value?)
        context.t.settings.knowledgeIndex.debug.detail.lastUsageUpdate(
          value: value,
        ),
    ];

    return SlSurface(
      key: const ValueKey('knowledge_index_memory_stats_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t.settings.knowledgeIndex.debug.memorySynthesisTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              context.t.settings.knowledgeIndex.debug.memorySynthesisBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in chips)
                  Chip(
                    label: Text(chip),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final line in detailLines) ...[
              Text(line),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}
