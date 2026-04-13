import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/history.dart';
import '../../src/rust/knowledge/pages.dart';
import '../../ui/sl_surface.dart';
import 'knowledge_page_display_text.dart';

class KnowledgePageHistoryView extends StatelessWidget {
  const KnowledgePageHistoryView({
    required this.pageTitle,
    required this.history,
    required this.versionSnapshots,
    super.key,
  });

  final String pageTitle;
  final List<KnowledgePageChangeRecord> history;
  final List<KnowledgePageVersionSnapshot> versionSnapshots;

  static Future<void> open(
    BuildContext context, {
    required String pageTitle,
    required List<KnowledgePageChangeRecord> history,
    required List<KnowledgePageVersionSnapshot> versionSnapshots,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KnowledgePageHistoryView(
          pageTitle: pageTitle,
          history: history,
          versionSnapshots: versionSnapshots,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.memory.views.history)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HistorySection(
            title: context.t.memory.detail.versionHistory,
            children: versionSnapshots.isEmpty
                ? [Text(context.t.memory.detail.noVersionSnapshots)]
                : versionSnapshots
                    .map((snapshot) => _VersionSnapshotTile(snapshot: snapshot))
                    .toList(growable: false),
          ),
          const SizedBox(height: 16),
          _HistorySection(
            title: context.t.memory.detail.history,
            children: history.isEmpty
                ? [Text(context.t.memory.history.noReason)]
                : history
                    .map((item) => _HistoryRecordTile(item: item))
                    .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _HistoryRecordTile extends StatelessWidget {
  const _HistoryRecordTile({required this.item});

  final KnowledgePageChangeRecord item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            knowledgePageChangeTypeLabel(context.t, item.changeType),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(item.reason ?? context.t.memory.history.noReason),
          const SizedBox(height: 6),
          Text(
            _metaLine(
              first: item.actor,
              second: knowledgePageUpdatedLabel(
                context.t,
                item.createdAtMs.toInt(),
              ),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _VersionSnapshotTile extends StatelessWidget {
  const _VersionSnapshotTile({required this.snapshot});

  final KnowledgePageVersionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(snapshot.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            _metaLine(
              first:
                  knowledgePageChangeTypeLabel(context.t, snapshot.changeType),
              second: knowledgePageStateLabel(context.t, snapshot.state),
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            snapshot.summary.trim().isEmpty ? snapshot.body : snapshot.summary,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            _metaLine(
              first: snapshot.actor,
              second: knowledgePageUpdatedLabel(
                context.t,
                snapshot.createdAtMs.toInt(),
              ),
            ),
            style: theme.textTheme.bodySmall,
          ),
          if ((snapshot.reason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              snapshot.reason!,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

String _metaLine({
  required String first,
  required String second,
}) =>
    '$first \u00b7 $second';
