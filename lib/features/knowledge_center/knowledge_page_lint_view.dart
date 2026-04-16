import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/lint.dart';
import '../../ui/sl_surface.dart';
import 'knowledge_page_display_text.dart';

class KnowledgePageLintView extends StatelessWidget {
  const KnowledgePageLintView({
    required this.pageTitle,
    required this.records,
    super.key,
  });

  final String pageTitle;
  final List<KnowledgeLintRecord> records;

  static Future<void> open(
    BuildContext context, {
    required String pageTitle,
    required List<KnowledgeLintRecord> records,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => KnowledgePageLintView(
          pageTitle: pageTitle,
          records: records,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t.memory.views.review)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = records[index];
          return SlSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  knowledgeLintKindLabel(context.t, item.kind),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(item.summary),
                const SizedBox(height: 6),
                Text(
                  knowledgePageUpdatedLabel(
                      context.t, item.createdAtMs.toInt()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
