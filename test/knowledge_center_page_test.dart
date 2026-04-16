import 'dart:async';
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

part 'knowledge_center_page_test_support.dart';

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
      'KnowledgeCenterPage exposes a search entry that opens the search page without debug controls',
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
      recentChanges: const [],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 11)),
              lock: () {},
              child: const KnowledgeCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('knowledge_center_search')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('knowledge_center_search')));
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsWidgets);
    expect(find.text('Query'), findsOneWidget);
    expect(find.text('Use model'), findsNothing);
    expect(find.text('Process pending'), findsNothing);
    expect(find.text('Rebuild embeddings'), findsNothing);
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

  testWidgets('KnowledgeCenterPage hides removed pages from My Wiki',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _KnowledgeCenterBackendStub(
      summaries: [
        _summary(
          pageId: 'page:preferences',
          title: 'Preferences',
          pageType: KnowledgePageType.preferences,
          state: KnowledgePageState.removed,
          updatedAtMs: nowMs,
        ),
      ],
      details: {
        'page:preferences': _detail(
          pageId: 'page:preferences',
          title: 'Preferences',
          pageType: KnowledgePageType.preferences,
          state: KnowledgePageState.removed,
          summary: 'Removed preference page.',
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
              sessionKey: Uint8List.fromList(List<int>.filled(32, 6)),
              lock: () {},
              child: const KnowledgeCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Preferences'), findsNothing);
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

  testWidgets(
      'KnowledgeCenterPage loads missing recent change details concurrently',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _ConcurrentKnowledgeCenterBackendStub(
      details: {
        'page:preferences': _detail(
          pageId: 'page:preferences',
          title: 'Preferences',
          pageType: KnowledgePageType.preferences,
          state: KnowledgePageState.removed,
          summary: 'Removed preference page.',
          updatedAtMs: nowMs,
        ),
        'page:recent-events': _detail(
          pageId: 'page:recent-events',
          title: 'Recent Events',
          pageType: KnowledgePageType.recentEvents,
          state: KnowledgePageState.removed,
          summary: 'Removed events page.',
          updatedAtMs: nowMs - 1000,
        ),
      },
      recentChanges: [
        KnowledgePageChangeRecord(
          changeId: 'change:preferences',
          pageId: 'page:preferences',
          changeType: KnowledgePageChangeType.removed,
          actor: 'user',
          reason: 'Removed preference page.',
          answerImpacted: true,
          createdAtMs: nowMs,
        ),
        KnowledgePageChangeRecord(
          changeId: 'change:recent-events',
          pageId: 'page:recent-events',
          changeType: KnowledgePageChangeType.removed,
          actor: 'user',
          reason: 'Removed recent events page.',
          answerImpacted: true,
          createdAtMs: nowMs - 1000,
        ),
      ],
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 7)),
              lock: () {},
              child: const KnowledgeCenterPage(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(backend.requestedPageIds, [
      'page:preferences',
      'page:recent-events',
    ]);

    backend.completeAll();
    await tester.pumpAndSettle();

    expect(find.text('Recent Changes'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Recent Events'), findsOneWidget);
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

  testWidgets(
      'KnowledgeCenterPage refreshes directory entries after page changes',
      (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _MutableKnowledgeCenterBackendStub(
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
              sessionKey: Uint8List.fromList(List<int>.filled(32, 8)),
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

    await tester.tap(find.text('Topic Alpha'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Archive Page'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Topic Alpha'), findsNothing);
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
