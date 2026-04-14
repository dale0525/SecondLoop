import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/knowledge_center/knowledge_center_page.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/src/rust/knowledge/history.dart';
import 'package:secondloop/src/rust/knowledge/lint.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('KnowledgeCenterPage renders the final wiki portal sections',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _KnowledgeCenterBackendStub(
      summaries: [
        _summary(
          pageId: 'page:about-me',
          title: 'About Me',
          pageType: KnowledgePageType.aboutMe,
          state: KnowledgePageState.active,
          updatedAtMs: nowMs,
          lastUsedAtMs: nowMs,
        ),
        _summary(
          pageId: 'page:preferences',
          title: 'Preferences',
          pageType: KnowledgePageType.preferences,
          state: KnowledgePageState.active,
          updatedAtMs: nowMs - 1000,
          lastUsedAtMs: nowMs - 1000,
        ),
        _summary(
          pageId: 'page:current-focus',
          title: 'Current Focus',
          pageType: KnowledgePageType.currentFocus,
          state: KnowledgePageState.active,
          updatedAtMs: nowMs - 2000,
        ),
        _summary(
          pageId: 'page:recent-events',
          title: 'Recent Events',
          pageType: KnowledgePageType.recentEvents,
          state: KnowledgePageState.needsReview,
          updatedAtMs: nowMs - 3000,
        ),
      ],
      details: {
        'page:about-me': _detail(
          pageId: 'page:about-me',
          title: 'About Me',
          pageType: KnowledgePageType.aboutMe,
          state: KnowledgePageState.active,
          summary: 'Stable identity details.',
          updatedAtMs: nowMs,
        ),
        'page:preferences': _detail(
          pageId: 'page:preferences',
          title: 'Preferences',
          pageType: KnowledgePageType.preferences,
          state: KnowledgePageState.active,
          summary: 'Reply in Chinese by default.',
          updatedAtMs: nowMs - 1000,
          history: [
            KnowledgePageChangeRecord(
              changeId: 'change:preferences',
              pageId: 'page:preferences',
              changeType: KnowledgePageChangeType.updated,
              actor: 'system',
              reason: 'Preferences refreshed from recent evidence.',
              answerImpacted: true,
              createdAtMs: nowMs,
            ),
          ],
        ),
        'page:current-focus': _detail(
          pageId: 'page:current-focus',
          title: 'Current Focus',
          pageType: KnowledgePageType.currentFocus,
          state: KnowledgePageState.active,
          summary: 'Knowledge center migration.',
          updatedAtMs: nowMs - 2000,
        ),
        'page:recent-events': _detail(
          pageId: 'page:recent-events',
          title: 'Recent Events',
          pageType: KnowledgePageType.recentEvents,
          state: KnowledgePageState.needsReview,
          summary: 'Conflicting timing evidence.',
          updatedAtMs: nowMs - 3000,
          lintRecords: const [
            KnowledgeLintRecord(
              lintId: 'lint:recent-events:conflict',
              pageId: 'page:recent-events',
              kind: KnowledgeLintKind.conflict,
              summary: 'Conflicting evidence needs review.',
              createdAtMs: 1,
            ),
          ],
        ),
      },
      recentChanges: [
        KnowledgePageChangeRecord(
          changeId: 'change:1',
          pageId: 'page:preferences',
          changeType: KnowledgePageChangeType.updated,
          actor: 'system',
          reason: 'Preferences refreshed from recent evidence.',
          answerImpacted: true,
          createdAtMs: nowMs,
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
              child: const KnowledgeCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Current Me'), findsOneWidget);
    expect(find.text('Needs Your Attention'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recent Changes'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent Changes'), findsOneWidget);
    expect(find.text('Preferences refreshed from recent evidence.'),
        findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('My Wiki'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('My Wiki'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('System Activity'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('System Activity'), findsOneWidget);
    expect(find.text('About Me'), findsWidgets);
    expect(find.text('Preferences'), findsWidgets);
    expect(find.text('Current Focus'), findsWidgets);
    expect(find.text('Recent Events'), findsWidgets);
    expect(
        find.textContaining('Pages used in answers recently'), findsOneWidget);
  });

  testWidgets(
      'KnowledgeCenterPage keeps removed pages visible in recent changes',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _KnowledgeCenterBackendStub(
      summaries: [
        _summary(
          pageId: 'page:about-me',
          title: 'About Me',
          pageType: KnowledgePageType.aboutMe,
          state: KnowledgePageState.active,
          updatedAtMs: nowMs,
          lastUsedAtMs: nowMs,
        ),
      ],
      details: {
        'page:about-me': _detail(
          pageId: 'page:about-me',
          title: 'About Me',
          pageType: KnowledgePageType.aboutMe,
          state: KnowledgePageState.active,
          summary: 'Stable identity details.',
          updatedAtMs: nowMs,
        ),
        'page:preferences': _detail(
          pageId: 'page:preferences',
          title: 'Preferences',
          pageType: KnowledgePageType.preferences,
          state: KnowledgePageState.removed,
          summary: 'Removed preference page.',
          updatedAtMs: nowMs - 1000,
        ),
      },
      recentChanges: [
        KnowledgePageChangeRecord(
          changeId: 'change:removed',
          pageId: 'page:preferences',
          changeType: KnowledgePageChangeType.removed,
          actor: 'user',
          reason: 'Removed because it should not be used.',
          answerImpacted: true,
          createdAtMs: nowMs,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 2)),
              lock: () {},
              child: const KnowledgeCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Recent Changes'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Removed because it should not be used.'), findsOneWidget);
  });

  testWidgets(
      'KnowledgeCenterPage still renders recent changes when active summaries are empty',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _KnowledgeCenterBackendStub(
      summaries: const [],
      details: {
        'page:preferences': _detail(
          pageId: 'page:preferences',
          title: 'Preferences',
          pageType: KnowledgePageType.preferences,
          state: KnowledgePageState.removed,
          summary: 'Removed preference page.',
          updatedAtMs: nowMs - 1000,
        ),
      },
      recentChanges: [
        KnowledgePageChangeRecord(
          changeId: 'change:removed-only',
          pageId: 'page:preferences',
          changeType: KnowledgePageChangeType.removed,
          actor: 'user',
          reason: 'Removed because it should not be used.',
          answerImpacted: true,
          createdAtMs: nowMs,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 4)),
              lock: () {},
              child: const KnowledgeCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Recent Changes'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Removed because it should not be used.'), findsOneWidget);
    expect(find.text('No pages yet.'), findsNothing);
  });

  testWidgets(
      'KnowledgeCenterPage skips unreadable recent change details instead of failing the page',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _KnowledgeCenterBackendStub(
      summaries: [
        _summary(
          pageId: 'page:about-me',
          title: 'About Me',
          pageType: KnowledgePageType.aboutMe,
          state: KnowledgePageState.active,
          updatedAtMs: nowMs,
          lastUsedAtMs: nowMs,
        ),
      ],
      details: {
        'page:about-me': _detail(
          pageId: 'page:about-me',
          title: 'About Me',
          pageType: KnowledgePageType.aboutMe,
          state: KnowledgePageState.active,
          summary: 'Stable identity details.',
          updatedAtMs: nowMs,
        ),
      },
      recentChanges: [
        KnowledgePageChangeRecord(
          changeId: 'change:missing',
          pageId: 'page:preferences',
          changeType: KnowledgePageChangeType.removed,
          actor: 'user',
          reason: 'Removed because it should not be used.',
          answerImpacted: true,
          createdAtMs: nowMs,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 3)),
              lock: () {},
              child: const KnowledgeCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Current Me'), findsOneWidget);
    expect(find.text('About Me'), findsWidgets);
    expect(find.textContaining('loadFailed'), findsNothing);
  });

  testWidgets('KnowledgeCenterPage opens a directory list for page types',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _KnowledgeCenterBackendStub(
      summaries: [
        _summary(
          pageId: 'page:topics:alpha',
          title: 'Topic Alpha',
          pageType: KnowledgePageType.topics,
          state: KnowledgePageState.active,
          updatedAtMs: nowMs,
        ),
        _summary(
          pageId: 'page:topics:beta',
          title: 'Topic Beta',
          pageType: KnowledgePageType.topics,
          state: KnowledgePageState.active,
          updatedAtMs: nowMs - 1000,
        ),
      ],
      details: {
        'page:topics:alpha': _detail(
          pageId: 'page:topics:alpha',
          title: 'Topic Alpha',
          pageType: KnowledgePageType.topics,
          state: KnowledgePageState.active,
          summary: 'Alpha summary.',
          updatedAtMs: nowMs,
        ),
        'page:topics:beta': _detail(
          pageId: 'page:topics:beta',
          title: 'Topic Beta',
          pageType: KnowledgePageType.topics,
          state: KnowledgePageState.active,
          summary: 'Beta summary.',
          updatedAtMs: nowMs - 1000,
        ),
      },
      recentChanges: const [],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 3)),
              lock: () {},
              child: const KnowledgeCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('My Wiki'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Topics'));
    await tester.pumpAndSettle();

    expect(find.text('Topic Alpha'), findsOneWidget);
    expect(find.text('Topic Beta'), findsOneWidget);
  });

  testWidgets('KnowledgeCenterPage localizes portal sections in zh_CN',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _KnowledgeCenterBackendStub(
      summaries: [
        _summary(
          pageId: 'page:about-me',
          title: 'About Me',
          pageType: KnowledgePageType.aboutMe,
          state: KnowledgePageState.active,
          updatedAtMs: nowMs,
          lastUsedAtMs: nowMs,
        ),
      ],
      details: {
        'page:about-me': _detail(
          pageId: 'page:about-me',
          title: 'About Me',
          pageType: KnowledgePageType.aboutMe,
          state: KnowledgePageState.active,
          summary: 'Stable identity details.',
          updatedAtMs: nowMs,
        ),
      },
      recentChanges: const [],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 5)),
              lock: () {},
              child: const KnowledgeCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('当前的我'), findsOneWidget);
    expect(find.text('需要你处理'), findsOneWidget);
    expect(find.text('我的 Wiki'), findsOneWidget);
    expect(find.text('系统活动'), findsOneWidget);
    expect(find.text('关于我'), findsWidgets);
  });
}

final class _KnowledgeCenterBackendStub extends TestAppBackend
    implements KnowledgePagesBackend {
  _KnowledgeCenterBackendStub({
    required this.summaries,
    required this.details,
    required this.recentChanges,
  });

  final List<KnowledgePageSummary> summaries;
  final Map<String, KnowledgePageDetail> details;
  final List<KnowledgePageChangeRecord> recentChanges;

  @override
  Future<List<KnowledgePageSummary>> listKnowledgePageSummaries(
    Uint8List key,
  ) async =>
      summaries;

  @override
  Future<KnowledgePageDetail> getKnowledgePageDetail(
    Uint8List key, {
    required String pageId,
  }) async =>
      details[pageId] ?? (throw StateError('missing detail for $pageId'));

  @override
  Future<List<KnowledgePageChangeRecord>> listRecentKnowledgePageChanges(
    Uint8List key, {
    int limit = 8,
  }) async =>
      recentChanges.take(limit).toList(growable: false);

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
}

KnowledgePageSummary _summary({
  required String pageId,
  required String title,
  required KnowledgePageType pageType,
  required KnowledgePageState state,
  required int updatedAtMs,
  int? lastUsedAtMs,
}) {
  return KnowledgePageSummary(
    pageId: pageId,
    pageType: pageType,
    title: title,
    currentSummary: '$title summary',
    state: state,
    answerPolicy: const KnowledgeAnswerPolicy(
      defaultAllowed: true,
      requiresTemporalFraming: false,
    ),
    updatedAtMs: updatedAtMs,
    lastUsedAtMs: lastUsedAtMs,
    sourceCount: 1,
    conflictCount: 0,
    humanCorrected: false,
    tags: const [],
    primaryEvidenceIds: const [],
  );
}

KnowledgePageDetail _detail({
  required String pageId,
  required String title,
  required KnowledgePageType pageType,
  required KnowledgePageState state,
  required String summary,
  required int updatedAtMs,
  List<KnowledgePageChangeRecord> history = const [],
  List<KnowledgeLintRecord> lintRecords = const [],
}) {
  return KnowledgePageDetail(
    page: KnowledgePage(
      pageId: pageId,
      pageType: pageType,
      title: title,
      currentSummary: summary,
      currentBody: '$summary\nExpanded body.',
      state: state,
      answerPolicy: const KnowledgeAnswerPolicy(
        defaultAllowed: true,
        requiresTemporalFraming: false,
      ),
      confidenceLevel: 0.9,
      createdAtMs: updatedAtMs - 1000,
      updatedAtMs: updatedAtMs,
      lastUsedAtMs: updatedAtMs,
      sourceCount: 1,
      conflictCount: 0,
      humanCorrected: false,
      tags: const [],
      primaryEvidenceIds: const ['doc:1'],
      relatedPageIds: const [],
    ),
    sourceDocumentIds: const ['doc:1'],
    claimIds: const ['claim:1'],
    history: history,
    versionSnapshots: const [],
    evidenceEntries: const [],
    lintRecords: lintRecords,
  );
}
