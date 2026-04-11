import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_backend.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/models.dart';
import '../../ui/sl_surface.dart';
import 'memory_center_models.dart';
import 'memory_detail_page.dart';

class MemoryCenterPage extends StatefulWidget {
  const MemoryCenterPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
          context,
          const MemoryCenterPage(),
        ),
      ),
    );
  }

  @override
  State<MemoryCenterPage> createState() => _MemoryCenterPageState();
}

class _MemoryCenterPageState extends State<MemoryCenterPage> {
  Future<List<MemoryCenterSectionData>>? _future;

  Future<List<MemoryCenterSectionData>> _load(BuildContext context) async {
    final t = context.t;
    final backend = AppBackendScope.of(context);
    final knowledgeBackend = maybeKnowledgeBackendFor(backend);
    final sessionKey = SessionScope.of(context).sessionKey;
    const pageSize = 200;
    if (knowledgeBackend == null) {
      throw StateError('knowledge_backend_unavailable');
    }
    final memoryDocuments = <ContentKnowledgeDocument>[];
    var offset = 0;
    while (true) {
      final page = await knowledgeBackend.listKnowledgeDocuments(
        sessionKey,
        limit: pageSize,
        offset: offset,
      );
      memoryDocuments.addAll(
        page.where(isMemoryCenterDocument),
      );
      if (page.length < pageSize) {
        break;
      }
      offset += pageSize;
    }
    return buildMemoryCenterSections(memoryDocuments, t);
  }

  void _reload() {
    setState(() {
      _future = _load(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MemoryCenterSectionData>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: Text(context.t.memory.title)),
            body: Center(
              child:
                  Text(context.t.errors.loadFailed(error: '${snapshot.error}')),
            ),
          );
        }

        final sections = snapshot.data ?? const <MemoryCenterSectionData>[];
        return Scaffold(
          appBar: AppBar(
            title: Text(context.t.memory.title),
          ),
          body: sections.isEmpty
              ? Center(child: Text(context.t.memory.emptyState))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final section in sections) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _sectionLabel(context, section.section),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final card in section.cards) ...[
                        SlSurface(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            title: Text(card.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  card.summary,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    statusLabel(context, card.status),
                                    context.t.memory.meta.sourceCount(
                                      count: card.sourceCount,
                                    ),
                                    _updatedLabel(
                                      context,
                                      updatedAtMs: card.updatedAtMs,
                                    ),
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () async {
                              await MemoryDetailPage.openDocumentId(
                                context,
                                documentId: card.documentId,
                              );
                              if (!mounted) return;
                              _reload();
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

String _sectionLabel(BuildContext context, MemoryCenterSection section) {
  return switch (section) {
    MemoryCenterSection.preferences => context.t.memory.sections.preferences,
    MemoryCenterSection.people => context.t.memory.sections.people,
    MemoryCenterSection.projects => context.t.memory.sections.projects,
    MemoryCenterSection.topics => context.t.memory.sections.topics,
    MemoryCenterSection.recentEvents => context.t.memory.sections.recentEvents,
  };
}

String _updatedLabel(BuildContext context, {required int updatedAtMs}) {
  final delta = DateTime.now().millisecondsSinceEpoch - updatedAtMs;
  if (delta < const Duration(days: 1).inMilliseconds) {
    return context.t.memory.meta.updatedToday;
  }
  final dayCount = (delta / const Duration(days: 1).inMilliseconds).floor();
  if (dayCount <= 7) {
    return context.t.memory.meta.updatedDaysAgo(count: dayCount);
  }
  final date = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final formatted =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return context.t.memory.meta.updatedOn(date: formatted);
}
