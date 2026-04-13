import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_backend.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/pages.dart';
import '../../ui/sl_surface.dart';
import 'knowledge_center_models.dart';
import 'knowledge_page_display_text.dart';
import 'knowledge_page_detail.dart';

class KnowledgeCenterPage extends StatefulWidget {
  const KnowledgeCenterPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => wrapPushedPageWithInheritedScopes(
            context, const KnowledgeCenterPage()),
      ),
    );
  }

  @override
  State<KnowledgeCenterPage> createState() => _KnowledgeCenterPageState();
}

class _KnowledgeCenterPageState extends State<KnowledgeCenterPage> {
  Future<_KnowledgeCenterViewData>? _future;
  Uint8List? _loadedSessionKey;
  AppBackend? _loadedBackend;

  Future<_KnowledgeCenterViewData> _load(BuildContext context) async {
    final backend = maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    final sessionKey = SessionScope.of(context).sessionKey;
    if (backend == null) {
      throw StateError('knowledge_pages_backend_unavailable');
    }
    final summaries = await backend.listKnowledgePageSummaries(sessionKey);
    final recentChangeRecords = await backend.listRecentKnowledgePageChanges(
      sessionKey,
      limit: 8,
    );
    final detailsByPageId = <String, KnowledgePageDetail>{};
    for (final summary in summaries) {
      detailsByPageId[summary.pageId] = await backend.getKnowledgePageDetail(
        sessionKey,
        pageId: summary.pageId,
      );
    }
    return _KnowledgeCenterViewData(
      summaries: summaries,
      detailsByPageId: detailsByPageId,
      homeData: buildKnowledgeCenterHomeData(
        summaries: summaries,
        detailsByPageId: detailsByPageId,
        recentChangeRecords: recentChangeRecords,
      ),
    );
  }

  void _reload() {
    setState(() {
      _future = _load(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessionKey = Uint8List.fromList(SessionScope.of(context).sessionKey);
    final backend = AppBackendScope.of(context);
    final shouldReload = _future == null ||
        !listEquals(_loadedSessionKey, sessionKey) ||
        !identical(_loadedBackend, backend);
    if (shouldReload) {
      _loadedSessionKey = sessionKey;
      _loadedBackend = backend;
      _future = _load(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_KnowledgeCenterViewData>(
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

        final viewData = snapshot.data!;
        final home = viewData.homeData;
        return Scaffold(
          appBar: AppBar(title: Text(context.t.memory.title)),
          body: viewData.summaries.isEmpty
              ? Center(child: Text(context.t.memory.emptyState))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SectionHeader(
                      title: knowledgeCenterSectionLabel(
                        context.t,
                        KnowledgeCenterSectionKey.currentMe,
                      ),
                    ),
                    ...home.currentMe
                        .map((page) => _PageTile(page: page, onOpen: _openPage))
                        .expand(
                            (widget) => [widget, const SizedBox(height: 10)]),
                    const SizedBox(height: 6),
                    _SectionHeader(
                      title: knowledgeCenterSectionLabel(
                        context.t,
                        KnowledgeCenterSectionKey.needsAttention,
                      ),
                    ),
                    if (home.needsAttention.isEmpty)
                      _EmptySurface(label: context.t.memory.emptyState)
                    else
                      ...home.needsAttention
                          .map(
                            (page) => _AttentionTile(
                              page: page,
                              reason: knowledgeAttentionReason(
                                context.t,
                                page,
                                viewData.detailsByPageId[page.pageId],
                              ),
                              onOpen: _openPage,
                            ),
                          )
                          .expand(
                              (widget) => [widget, const SizedBox(height: 10)]),
                    const SizedBox(height: 6),
                    _SectionHeader(
                      title: knowledgeCenterSectionLabel(
                        context.t,
                        KnowledgeCenterSectionKey.recentChanges,
                      ),
                    ),
                    if (home.recentChanges.isEmpty)
                      _EmptySurface(label: context.t.memory.emptyState)
                    else
                      ...home.recentChanges
                          .map(
                            (item) => _RecentChangeTile(
                              item: item,
                              onOpen: _openPage,
                            ),
                          )
                          .expand(
                              (widget) => [widget, const SizedBox(height: 10)]),
                    const SizedBox(height: 6),
                    _SectionHeader(
                      title: knowledgeCenterSectionLabel(
                        context.t,
                        KnowledgeCenterSectionKey.myWiki,
                      ),
                    ),
                    ...home.directory
                        .map(
                          (entry) => _DirectoryTile(
                            entry: entry,
                            onOpen: _openPage,
                          ),
                        )
                        .expand(
                            (widget) => [widget, const SizedBox(height: 10)]),
                    const SizedBox(height: 6),
                    _SectionHeader(
                      title: knowledgeCenterSectionLabel(
                        context.t,
                        KnowledgeCenterSectionKey.systemActivity,
                      ),
                    ),
                    _SystemActivityTile(activity: home.systemActivity),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _openPage(KnowledgePageSummary page) async {
    await KnowledgePageDetailPage.openPageId(
      context,
      pageId: page.pageId,
    );
    if (!mounted) return;
    _reload();
  }
}

class _KnowledgeCenterViewData {
  const _KnowledgeCenterViewData({
    required this.summaries,
    required this.detailsByPageId,
    required this.homeData,
  });

  final List<KnowledgePageSummary> summaries;
  final Map<String, KnowledgePageDetail> detailsByPageId;
  final KnowledgeCenterHomeData homeData;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.page,
    required this.onOpen,
  });

  final KnowledgePageSummary page;
  final Future<void> Function(KnowledgePageSummary page) onOpen;

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 6,
        ),
        title: Text(page.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (page.currentSummary.trim().isNotEmpty)
              Text(
                page.currentSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            Text(
              [
                knowledgePageStateLabel(context.t, page.state),
                context.t.memory.meta.sourceCount(
                  count: page.sourceCount,
                ),
                knowledgePageUpdatedLabel(
                  context.t,
                  page.updatedAtMs.toInt(),
                ),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => onOpen(page),
      ),
    );
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.page,
    required this.reason,
    required this.onOpen,
  });

  final KnowledgePageSummary page;
  final String reason;
  final Future<void> Function(KnowledgePageSummary page) onOpen;

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      child: ListTile(
        title: Text(page.title),
        subtitle: Text(reason),
        trailing: TextButton(
          onPressed: () => onOpen(page),
          child: Text(context.t.memory.homepage.reviewCta),
        ),
      ),
    );
  }
}

class _RecentChangeTile extends StatelessWidget {
  const _RecentChangeTile({
    required this.item,
    required this.onOpen,
  });

  final KnowledgeRecentChangeItem item;
  final Future<void> Function(KnowledgePageSummary page) onOpen;

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      child: ListTile(
        title: Text(item.page.title),
        subtitle: Text(knowledgeRecentChangeSummary(context.t, item)),
        trailing: Text(
          knowledgePageUpdatedLabel(context.t, item.record.createdAtMs.toInt()),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () => onOpen(item.page),
      ),
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({
    required this.entry,
    required this.onOpen,
  });

  final KnowledgeDirectoryEntry entry;
  final Future<void> Function(KnowledgePageSummary page) onOpen;

  @override
  Widget build(BuildContext context) {
    final leadPage = entry.pages.first;
    return SlSurface(
      child: ListTile(
        title: Text(knowledgePageTypeLabel(context.t, entry.pageType)),
        subtitle: Text(knowledgeDirectorySubtitle(context.t, entry)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => onOpen(leadPage),
      ),
    );
  }
}

class _SystemActivityTile extends StatelessWidget {
  const _SystemActivityTile({required this.activity});

  final KnowledgeSystemActivityData activity;

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t.memory.homepage.systemActivitySummary(
              totalPages: activity.totalPages,
              needsReview: activity.pagesNeedingReview,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.t.memory.homepage.pagesUsedInAnswersRecently,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (activity.pagesUsedInAnswersRecently.isEmpty)
            Text(context.t.memory.emptyState)
          else
            for (final page in activity.pagesUsedInAnswersRecently)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_bulletLine(page.title)),
              ),
        ],
      ),
    );
  }
}

String _bulletLine(String value) => '\u2022 $value';

class _EmptySurface extends StatelessWidget {
  const _EmptySurface({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SlSurface(
      padding: const EdgeInsets.all(14),
      child: Text(label),
    );
  }
}
