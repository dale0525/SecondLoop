import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/db.dart';
import '../../ui/sl_surface.dart';

String _formatLocalDay(DateTime value) {
  final dt = value.toLocal();
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _purposeLabel(BuildContext context, LlmUsageAggregate agg) {
  return switch (agg.purpose) {
    'ask_ai' => context.t.common.actions.askAi,
    'semantic_parse' => context.t.settings.byokUsage.purposes.semanticParse,
    'media_annotation' => context.t.settings.byokUsage.purposes.mediaAnnotation,
    _ => agg.purpose,
  };
}

String _formatTokens(LlmUsageAggregate agg) {
  if (agg.requestsWithUsage != agg.requests) return '—';
  return '${agg.inputTokens}/${agg.outputTokens}/${agg.totalTokens}';
}

Widget _usageRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

final class _UsageSummary {
  const _UsageSummary({
    required this.todayDay,
    required this.rangeStartDay,
    required this.today,
    required this.last30d,
  });

  final String todayDay;
  final String rangeStartDay;
  final List<LlmUsageAggregate> today;
  final List<LlmUsageAggregate> last30d;
}

class ByokUsageCard extends StatefulWidget {
  const ByokUsageCard({super.key, required this.activeProfile});

  final LlmProfile activeProfile;

  @override
  State<ByokUsageCard> createState() => _ByokUsageCardState();
}

class _ByokUsageCardState extends State<ByokUsageCard> {
  Future<_UsageSummary>? _summaryFuture;
  bool _busy = false;

  Future<_UsageSummary> _load() async {
    final backend = AppBackendScope.of(context);
    final sessionKey = SessionScope.of(context).sessionKey;

    final now = DateTime.now();
    final today = _formatLocalDay(now);
    final start = _formatLocalDay(now.subtract(const Duration(days: 29)));

    final todayAgg = await backend.sumLlmUsageDailyByPurpose(
      sessionKey,
      widget.activeProfile.id,
      startDay: today,
      endDay: today,
    );
    final last30dAgg = await backend.sumLlmUsageDailyByPurpose(
      sessionKey,
      widget.activeProfile.id,
      startDay: start,
      endDay: today,
    );
    return _UsageSummary(
      todayDay: today,
      rangeStartDay: start,
      today: todayAgg,
      last30d: last30dAgg,
    );
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      setState(() => _summaryFuture = _load());
      await _summaryFuture;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didUpdateWidget(covariant ByokUsageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeProfile.id != widget.activeProfile.id) {
      _summaryFuture = _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _summaryFuture ??= _load();
  }

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      key: const ValueKey('byok_usage_card'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t.settings.byokUsage.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t.settings.byokUsage.subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('byok_usage_refresh'),
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: context.t.common.actions.refresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder(
            future: _summaryFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Text(context.t.settings.byokUsage.loading);
              }
              if (snapshot.hasError) {
                return Text(
                  context.t.settings.byokUsage.errors
                      .unavailable(error: '${snapshot.error}'),
                );
              }

              final summary = snapshot.data;
              if (summary == null) return const SizedBox.shrink();

              Widget section(String title, List<LlmUsageAggregate> items) {
                if (items.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(context.t.settings.byokUsage.noData),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    for (final agg in items) ...[
                      _usageRow(
                        context.t.settings.byokUsage.labels.requests(
                          purpose: _purposeLabel(context, agg),
                        ),
                        '${agg.requests}',
                      ),
                      _usageRow(
                        context.t.settings.byokUsage.labels.tokens(
                          purpose: _purposeLabel(context, agg),
                        ),
                        _formatTokens(agg),
                      ),
                      const Divider(height: 16),
                    ],
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  section(
                    context.t.settings.byokUsage.sections.today(
                      day: summary.todayDay,
                    ),
                    summary.today,
                  ),
                  const SizedBox(height: 12),
                  section(
                    context.t.settings.byokUsage.sections.last30d(
                      start: summary.rangeStartDay,
                      end: summary.todayDay,
                    ),
                    summary.last30d,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
