import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/backend/app_backend.dart';
import '../../core/backend/knowledge_backend.dart';
import '../../core/navigation/inherited_scope_page_wrapper.dart';
import '../../core/session/session_scope.dart';
import '../../i18n/strings.g.dart';
import '../../src/rust/knowledge/pages.dart';
import '../../ui/sl_surface.dart';
import '../settings/semantic_search_debug_page.dart';
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
    final summariesByPageId = {
      for (final page in summaries) page.pageId: page,
    };
    final recentChangePagesById = <String, KnowledgePageSummary>{};
    final loadedMissingPageIds = <String>{};
    final missingRecentChangePageIds = recentChangeRecords
        .map((record) => record.pageId)
        .where((pageId) =>
            !summariesByPageId.containsKey(pageId) &&
            loadedMissingPageIds.add(pageId))
        .toList(growable: false);
    final missingRecentChangePages = await Future.wait(
      missingRecentChangePageIds.map((pageId) async {
        try {
          final detail = await backend.getKnowledgePageDetail(
            sessionKey,
            pageId: pageId,
          );
          return MapEntry(pageId, _summaryFromDetail(detail));
        } catch (_) {
          return null;
        }
      }),
    );
    for (final entry in missingRecentChangePages.nonNulls) {
      recentChangePagesById[entry.key] = entry.value;
    }
    return _KnowledgeCenterViewData(
      summaries: summaries,
      homeData: buildKnowledgeCenterHomeData(
        summaries: summaries,
        recentChangeRecords: recentChangeRecords,
        recentChangePagesById: recentChangePagesById,
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
        final hasVisibleContent = home.currentMe.isNotEmpty ||
            home.needsAttention.isNotEmpty ||
            home.recentChanges.isNotEmpty ||
            home.directory.isNotEmpty ||
            home.systemActivity.totalPages > 0 ||
            home.systemActivity.pagesUsedInAnswersRecently.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: Text(context.t.memory.title),
            actions: [
              IconButton(
                key: const ValueKey('knowledge_center_search'),
                tooltip: context.t.common.actions.search,
                icon: const Icon(Icons.search_rounded),
                onPressed: _openSearch,
              ),
            ],
          ),
          body: !hasVisibleContent
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

  Future<void> _openSearch() {
    return SemanticSearchDebugPage.openSearch(context);
  }
}

class _KnowledgeCenterViewData {
  const _KnowledgeCenterViewData({
    required this.summaries,
    required this.homeData,
  });

  final List<KnowledgePageSummary> summaries;
  final KnowledgeCenterHomeData homeData;
}

KnowledgePageSummary _summaryFromDetail(KnowledgePageDetail detail) {
  final page = detail.page;
  return KnowledgePageSummary(
    pageId: page.pageId,
    pageType: page.pageType,
    title: page.title,
    currentSummary: page.currentSummary,
    state: page.state,
    answerPolicy: page.answerPolicy,
    updatedAtMs: page.updatedAtMs,
    lastUsedAtMs: page.lastUsedAtMs,
    sourceCount: page.sourceCount,
    conflictCount: page.conflictCount,
    humanCorrected: page.humanCorrected,
    tags: page.tags,
    primaryEvidenceIds: page.primaryEvidenceIds,
  );
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
    return SlSurface(
      child: ListTile(
        title: Text(knowledgePageTypeLabel(context.t, entry.pageType)),
        subtitle: Text(knowledgeDirectorySubtitle(context.t, entry)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => wrapPushedPageWithInheritedScopes(
              context,
              _KnowledgeDirectoryListPage(
                entry: entry,
                onOpen: onOpen,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KnowledgeDirectoryListPage extends StatefulWidget {
  const _KnowledgeDirectoryListPage({
    required this.entry,
    required this.onOpen,
  });

  final KnowledgeDirectoryEntry entry;
  final Future<void> Function(KnowledgePageSummary page) onOpen;

  @override
  State<_KnowledgeDirectoryListPage> createState() =>
      _KnowledgeDirectoryListPageState();
}

class _KnowledgeDirectoryListPageState
    extends State<_KnowledgeDirectoryListPage> {
  Future<List<KnowledgePageSummary>>? _future;
  Uint8List? _loadedSessionKey;
  AppBackend? _loadedBackend;

  Future<List<KnowledgePageSummary>> _loadPages() async {
    final backend = maybeKnowledgePagesBackendFor(AppBackendScope.of(context));
    if (backend == null) {
      throw StateError('knowledge_pages_backend_unavailable');
    }
    final summaries = await backend.listKnowledgePageSummaries(
      SessionScope.of(context).sessionKey,
    );
    final pages = summaries
        .where((page) =>
            page.pageType == widget.entry.pageType &&
            page.state != KnowledgePageState.archived &&
            page.state != KnowledgePageState.removed)
        .toList(growable: false)
      ..sort((left, right) {
        final lastUsedCompare =
            (right.lastUsedAtMs ?? 0).compareTo(left.lastUsedAtMs ?? 0);
        if (lastUsedCompare != 0) return lastUsedCompare;
        return right.updatedAtMs.compareTo(left.updatedAtMs);
      });
    return pages;
  }

  void _reload() {
    setState(() {
      _future = _loadPages();
    });
  }

  Future<void> _openPage(KnowledgePageSummary page) async {
    await widget.onOpen(page);
    if (!mounted) return;
    _reload();
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
      _future = _loadPages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<KnowledgePageSummary>>(
      future: _future,
      builder: (context, snapshot) => Scaffold(
        appBar: AppBar(
          title: Text(knowledgePageTypeLabel(context.t, widget.entry.pageType)),
        ),
        body: snapshot.connectionState != ConnectionState.done
            ? const Center(child: CircularProgressIndicator())
            : snapshot.hasError
                ? Center(
                    child: Text(
                      context.t.errors.loadFailed(error: '${snapshot.error}'),
                    ),
                  )
                : (snapshot.data?.isEmpty ?? true)
                    ? Center(child: Text(context.t.memory.emptyState))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) => _PageTile(
                          page: snapshot.data![index],
                          onOpen: _openPage,
                        ),
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: snapshot.data!.length,
                      ),
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
