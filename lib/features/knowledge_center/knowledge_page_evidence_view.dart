import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/pages.dart';
import '../../ui/sl_surface.dart';
import '../knowledge_viewer/knowledge_document_viewer_page.dart';
import 'knowledge_page_display_text.dart';

class KnowledgePageEvidenceView extends StatelessWidget {
  const KnowledgePageEvidenceView({
    required this.pageTitle,
    required this.entries,
    super.key,
  });

  final String pageTitle;
  final List<KnowledgePageEvidenceEntry> entries;

  static Future<void> open(
    BuildContext context, {
    required String pageTitle,
    required List<KnowledgePageEvidenceEntry> entries,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KnowledgePageEvidenceView(
          pageTitle: pageTitle,
          entries: entries,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supportEntries = entries
        .where((entry) => entry.kind == KnowledgePageEvidenceKind.support)
        .toList(growable: false);
    final conflictEntries = entries
        .where((entry) => entry.kind == KnowledgePageEvidenceKind.conflict)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(context.t.memory.views.evidence)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SlSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t.memory.detail.evidenceSummary,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  context.t.memory.detail.sourceMix(
                    types: _sourceMixLabel(context.t, entries),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  supportEntries.isEmpty
                      ? context.t.memory.detail.noEvidenceEntries
                      : context.t.memory.detail.latestSupportingEvidence,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (supportEntries.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(supportEntries.first.summary),
                ],
                const SizedBox(height: 8),
                Text(
                  conflictEntries.isEmpty
                      ? context.t.memory.detail.conflictingEvidenceAbsent
                      : context.t.memory.detail.conflictingEvidencePresent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SlSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t.memory.detail.evidenceTimeline,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  Text(context.t.memory.detail.noEvidenceEntries),
                for (final entry in entries) _EvidenceEntryTile(entry: entry),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceEntryTile extends StatelessWidget {
  const _EvidenceEntryTile({required this.entry});

  final KnowledgePageEvidenceEntry entry;

  @override
  Widget build(BuildContext context) {
    final documentId = _primaryDocumentId(entry.sourceRefIds);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(entry.summary),
      subtitle: Text(
        _subtitle(
          kind: knowledgePageEvidenceKindLabel(context.t, entry.kind),
          source: entry.sourceRefIds.join(', '),
        ),
      ),
      trailing:
          documentId == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: documentId == null
          ? null
          : () => KnowledgeDocumentViewerPage.openDocumentId(
                context,
                documentId: documentId,
              ),
    );
  }
}

String _sourceMixLabel(
  Translations t,
  List<KnowledgePageEvidenceEntry> entries,
) {
  if (entries.isEmpty) {
    return t.memory.detail.noEvidenceEntries;
  }
  final buckets = <String, int>{};
  for (final entry in entries) {
    for (final ref in entry.sourceRefIds) {
      final key = _sourceTypeLabel(t, ref);
      buckets.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  final ordered = buckets.entries.toList()
    ..sort((left, right) => right.value.compareTo(left.value));
  return ordered.take(3).map((entry) => entry.key).join(', ');
}

String _sourceTypeLabel(Translations t, String ref) {
  if (ref.startsWith('message:')) {
    return t.memory.detail.sourceTypes.message;
  }
  if (ref.startsWith('attachment:')) {
    return t.memory.detail.sourceTypes.attachment;
  }
  if (ref.startsWith('generated:') || ref.startsWith('summary:')) {
    return t.memory.detail.sourceTypes.summary;
  }
  if (ref.startsWith('transcript:')) {
    return t.memory.detail.sourceTypes.transcript;
  }
  return t.memory.detail.sourceTypes.evidence;
}

String? _primaryDocumentId(List<String> sourceRefIds) {
  for (final ref in sourceRefIds) {
    if (!ref.startsWith('message:') && !ref.startsWith('attachment:')) {
      return ref;
    }
  }
  return null;
}

String _subtitle({
  required String kind,
  required String source,
}) =>
    '$kind \u00b7 $source';
