import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/knowledge_center/knowledge_center_models.dart';
import 'package:secondloop/features/memory/memory_center_page.dart';
import 'package:secondloop/src/rust/knowledge/history.dart';
import 'package:secondloop/src/rust/knowledge/lint.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  test('buildKnowledgeCenterHomeData creates final portal sections', () {
    final page = _pageSummary(
      pageId: 'page:preferences',
      title: 'Preferences',
      pageType: KnowledgePageType.preferences,
      state: KnowledgePageState.active,
      sourceCount: 2,
      updatedAtMs: 20,
      lastUsedAtMs: 25,
    );
    final reviewPage = _pageSummary(
      pageId: 'page:recent-events',
      title: 'Recent Events',
      pageType: KnowledgePageType.recentEvents,
      state: KnowledgePageState.needsReview,
      updatedAtMs: 40,
    );
    final home = buildKnowledgeCenterHomeData(
      summaries: [page, reviewPage],
      recentChangeRecords: const [
        KnowledgePageChangeRecord(
          changeId: 'change:1',
          pageId: 'page:preferences',
          changeType: KnowledgePageChangeType.updated,
          actor: 'system',
          reason: 'Updated from fresh evidence.',
          answerImpacted: true,
          createdAtMs: 30,
        ),
      ],
    );

    expect(home.currentMe.map((item) => item.title), ['Preferences']);
    expect(home.needsAttention.map((item) => item.title), ['Recent Events']);
    expect(
        home.recentChanges.first.record.reason, 'Updated from fresh evidence.');
    expect(home.directory.map((item) => item.pageType), [
      KnowledgePageType.preferences,
      KnowledgePageType.recentEvents,
    ]);
  });

  testWidgets('MemoryCenterPage renders grouped knowledge pages',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _KnowledgePagesBackendStub(
      pages: [
        _pageSummary(
          pageId: 'page:preferences:language',
          title: 'Response language',
          summary: 'Reply in Chinese unless another language is requested.',
          state: KnowledgePageState.active,
          sourceCount: 2,
          updatedAtMs: nowMs,
        ),
        _pageSummary(
          pageId: 'page:projects:launch',
          title: 'Launch plan',
          summary: 'Rollout timing needs confirmation.',
          state: KnowledgePageState.needsReview,
          sourceCount: 3,
          updatedAtMs: nowMs - const Duration(days: 1).inMilliseconds,
        ),
        _pageSummary(
          pageId: 'page:topics:parking-lot',
          title: 'Parking lot',
          summary: 'Ideas that should not be used in answers.',
          state: KnowledgePageState.answerMuted,
          sourceCount: 1,
          updatedAtMs: nowMs - const Duration(days: 2).inMilliseconds,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const MemoryCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Current Me'), findsOneWidget);
    expect(find.text('Needs Your Attention'), findsOneWidget);
    expect(find.text('Recent Changes'), findsOneWidget);
    expect(find.text('Response language'), findsOneWidget);
    expect(find.text('Launch plan'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('My Wiki'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('My Wiki'), findsOneWidget);
    expect(find.textContaining('pages'), findsWidgets);
  });

  testWidgets('MemoryCenterPage does not reload on unrelated parent rebuild',
      (tester) async {
    final backend = _KnowledgePagesBackendStub(
      pages: [
        _pageSummary(
          pageId: 'page:preferences:language',
          title: 'Response language',
          state: KnowledgePageState.active,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const _MemoryCenterHarness(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(backend.requestedSessionLeads, <int>[1]);

    await tester
        .tap(find.byKey(const ValueKey('memory_center_harness_rebuild')));
    await tester.pumpAndSettle();

    expect(backend.requestedSessionLeads, <int>[1]);
  });

  testWidgets('MemoryCenterPage reloads when the session changes',
      (tester) async {
    final backend = _KnowledgePagesBackendStub(
      pagesForKey: (key) => <KnowledgePageSummary>[
        _pageSummary(
          pageId: 'page:session:${key.first}',
          title: key.first == 1 ? 'Session one page' : 'Session two page',
          state: KnowledgePageState.active,
          updatedAtMs: key.first,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: const _SwitchingSessionHarness(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Session one page'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('switch_session_button')));
    await tester.pumpAndSettle();

    expect(find.text('Session one page'), findsNothing);
    expect(find.text('Session two page'), findsWidgets);
    expect(backend.requestedSessionLeads, <int>[1, 2]);
  });
}

final class _KnowledgePagesBackendStub extends TestAppBackend
    implements KnowledgePagesBackend {
  _KnowledgePagesBackendStub({
    List<KnowledgePageSummary>? pages,
    this.pagesForKey,
  }) : _pages = pages ?? const <KnowledgePageSummary>[];

  final List<KnowledgePageSummary> _pages;
  final List<KnowledgePageSummary> Function(Uint8List key)? pagesForKey;
  final List<int> requestedSessionLeads = <int>[];

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async {
    requestedSessionLeads.add(key.first);
    return List<KnowledgePageSummary>.from(pagesForKey?.call(key) ?? _pages);
  }

  @override
  Future<List<KnowledgePageSummary>> listMergeableKnowledgePageSummaries(
    Uint8List key, {
    required String pageId,
  }) async =>
      const <KnowledgePageSummary>[];

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async =>
      KnowledgePageDetail(
        page: _page(
          pageId: pageId,
          title: 'Detail $pageId',
          pageType: KnowledgePageType.preferences,
          state: KnowledgePageState.active,
        ),
        sourceDocumentIds: const <String>[],
        claimIds: const <String>[],
        history: const <KnowledgePageChangeRecord>[],
        versionSnapshots: const <KnowledgePageVersionSnapshot>[],
        evidenceEntries: const <KnowledgePageEvidenceEntry>[],
        lintRecords: const <KnowledgeLintRecord>[],
      );

  @override
  Future<List<KnowledgePageChangeRecord>> listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) async =>
      const <KnowledgePageChangeRecord>[];

  @override
  Future<KnowledgePageDetail> correctKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? title,
    String? summary,
    String? body,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> markKnowledgePageWrong(
    Uint8List key, {
    required String pageId,
    required KnowledgeWrongReason reason,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> setKnowledgePageAnswerAllowed(
    Uint8List key, {
    required String pageId,
    required bool allowed,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> archiveKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> removeKnowledgePage(
    Uint8List key, {
    required String pageId,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgePageDetail> mergeKnowledgePageInto(
    Uint8List key, {
    required String pageId,
    required String targetPageId,
    String? note,
  }) async =>
      throw UnimplementedError();
}

class _MemoryCenterHarness extends StatefulWidget {
  const _MemoryCenterHarness();

  @override
  State<_MemoryCenterHarness> createState() => _MemoryCenterHarnessState();
}

class _MemoryCenterHarnessState extends State<_MemoryCenterHarness> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          key: const ValueKey('memory_center_harness_rebuild'),
          onPressed: () => setState(() => _counter += 1),
          child: Text('Rebuild $_counter'),
        ),
        const Expanded(child: MemoryCenterPage()),
      ],
    );
  }
}

class _SwitchingSessionHarness extends StatefulWidget {
  const _SwitchingSessionHarness();

  @override
  State<_SwitchingSessionHarness> createState() =>
      _SwitchingSessionHarnessState();
}

class _SwitchingSessionHarnessState extends State<_SwitchingSessionHarness> {
  late Uint8List _sessionKey;

  @override
  void initState() {
    super.initState();
    _sessionKey = Uint8List.fromList(List<int>.filled(32, 1));
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      sessionKey: _sessionKey,
      lock: () {},
      child: Column(
        children: [
          TextButton(
            key: const ValueKey('switch_session_button'),
            onPressed: () {
              setState(() {
                _sessionKey = Uint8List.fromList(List<int>.filled(32, 2));
              });
            },
            child: const Text('Switch'),
          ),
          const Expanded(child: MemoryCenterPage()),
        ],
      ),
    );
  }
}

KnowledgePageSummary _pageSummary({
  required String pageId,
  required String title,
  KnowledgePageType pageType = KnowledgePageType.preferences,
  String summary = 'Summary',
  KnowledgePageState state = KnowledgePageState.active,
  int updatedAtMs = 1,
  int? lastUsedAtMs,
  int sourceCount = 1,
}) {
  return KnowledgePageSummary(
    pageId: pageId,
    pageType: pageType,
    title: title,
    currentSummary: summary,
    state: state,
    answerPolicy: const KnowledgeAnswerPolicy(
      defaultAllowed: true,
      requiresTemporalFraming: false,
    ),
    updatedAtMs: updatedAtMs,
    lastUsedAtMs: lastUsedAtMs,
    sourceCount: sourceCount,
    conflictCount: 0,
    humanCorrected: false,
    tags: const <String>[],
    primaryEvidenceIds: const <String>[],
  );
}

KnowledgePage _page({
  required String pageId,
  required String title,
  required KnowledgePageType pageType,
  required KnowledgePageState state,
  int updatedAtMs = 1,
}) {
  return KnowledgePage(
    pageId: pageId,
    pageType: pageType,
    title: title,
    currentSummary: 'Summary',
    currentBody: 'Body',
    state: state,
    answerPolicy: const KnowledgeAnswerPolicy(
      defaultAllowed: true,
      requiresTemporalFraming: false,
    ),
    confidenceLevel: 0.9,
    createdAtMs: 1,
    updatedAtMs: updatedAtMs,
    lastUsedAtMs: null,
    sourceCount: 1,
    conflictCount: 0,
    humanCorrected: false,
    tags: const <String>[],
    primaryEvidenceIds: const <String>[],
    relatedPageIds: const <String>[],
  );
}
