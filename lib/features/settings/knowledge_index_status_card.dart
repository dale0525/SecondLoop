import 'package:flutter/material.dart';

import '../../core/backend/knowledge_index_models.dart';
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
      'Total ${stats.totalDocuments}',
      'Generated ${stats.generatedDocuments}',
      'Source ${stats.sourceDocuments}',
      'Summaries ${stats.summaryDocuments}',
      'Preferences ${stats.preferenceDocuments}',
      'Profiles ${stats.profileDocuments}',
      'Events ${stats.eventDocuments}',
      'Patterns ${stats.patternDocuments}',
      'Usage rows ${stats.usageStatDocuments}',
    ];
    final detailLines = <String>[
      'Generated memory retrieval: ${stats.generatedMemoryRetrievalEnabled ? 'on' : 'off'}',
      'Hotness rerank: ${stats.hotnessRerankEnabled ? 'on' : 'off'}',
      'Session digest: ${stats.sessionDigestEnabled ? 'on' : 'off'}',
      if (_formatTimestamp(stats.lastSynthesisAtMs) case final value?)
        'Last synthesis: $value',
      if (_formatTimestamp(stats.lastRetrievedAtMs) case final value?)
        'Last usage update: $value',
    ];

    return SlSurface(
      key: const ValueKey('knowledge_index_memory_stats_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Memory synthesis',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Generated memories stay local and encrypted inside the knowledge index.',
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
