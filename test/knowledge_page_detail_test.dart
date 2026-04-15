import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/knowledge_center/knowledge_page_detail.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/src/rust/knowledge/history.dart';
import 'package:secondloop/src/rust/knowledge/lint.dart';
import 'package:secondloop/src/rust/knowledge/pages.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

part 'knowledge_page_detail_test_support.dart';

void main() {
  testWidgets(
      'KnowledgePageDetailPage keeps summary and body separate when correcting',
      (tester) async {
    final backend = _MutableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Correct current conclusion'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('memory_correction_summary_field')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('memory_correction_body_field')),
        findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_summary_field')),
      'Short corrected summary.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_body_field')),
      'Detailed corrected body.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(backend.correctedSummary, 'Short corrected summary.');
    expect(backend.correctedBody, 'Detailed corrected body.');
  });

  testWidgets('KnowledgePageDetailPage only sends changed correction fields',
      (tester) async {
    final backend = _MutableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Correct current conclusion'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('memory_correction_summary_field')),
      'Short corrected summary.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(backend.correctedTitle, isNull);
    expect(backend.correctedSummary, 'Short corrected summary.');
    expect(backend.correctedBody, isNull);
  });

  testWidgets('KnowledgePageDetailPage reloads when the session key changes',
      (tester) async {
    final backend = _ReloadAwareKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(backend.loadCount, 1);
    expect(backend.lastLoadedKey, List<int>.filled(32, 1));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 2)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(backend.loadCount, 2);
    expect(backend.lastLoadedKey, List<int>.filled(32, 2));
  });

  testWidgets(
      'KnowledgePageDetailPage hides merge action for singleton page types',
      (tester) async {
    final backend = _MutableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Merge Pages'), findsNothing);
  });

  testWidgets(
      'KnowledgePageDetailPage hides merge action for unrelated mergeable topic pages',
      (tester) async {
    final backend = _UnrelatedMergeableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:topics:alpha'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Merge Pages'), findsNothing);
  });

  testWidgets(
      'KnowledgePageDetailPage shows merge action for mergeable topic pages and merges into target',
      (tester) async {
    final backend = _MergeableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:topics:alpha'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Merge Pages'), findsOneWidget);

    await tester.tap(find.text('Merge Pages'));
    await tester.pumpAndSettle();

    expect(find.text('Topic Beta'), findsOneWidget);
    await tester.tap(find.text('Topic Beta'));
    await tester.pumpAndSettle();

    expect(backend.mergedPageId, 'page:topics:alpha');
    expect(backend.mergedTargetPageId, 'page:topics:beta');
  });

  testWidgets(
      'KnowledgePageDetailPage shows merge action when reverse related page points back to current page',
      (tester) async {
    final backend = _ReverseRelatedMergeableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:topics:alpha'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Merge Pages'), findsOneWidget);

    await tester.tap(find.text('Merge Pages'));
    await tester.pumpAndSettle();

    expect(find.text('Topic Beta'), findsOneWidget);
    await tester.tap(find.text('Topic Beta'));
    await tester.pumpAndSettle();

    expect(backend.mergedPageId, 'page:topics:alpha');
    expect(backend.mergedTargetPageId, 'page:topics:beta');
  });

  testWidgets(
      'KnowledgePageDetailPage resolves merge targets without loading every candidate detail',
      (tester) async {
    final backend = _ReverseRelatedMergeableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:topics:alpha'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(backend.detailLoadPageIds, ['page:topics:alpha']);
    expect(backend.mergeSummaryLoadCount, 1);
  });

  testWidgets(
      'KnowledgePageDetailPage loads related page summaries by ids without listing the full directory',
      (tester) async {
    final backend = _RelatedSummaryKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(backend.fullSummaryLoadCount, 0);
    expect(
      backend.relatedSummaryRequests,
      [
        ['page:about-me', 'page:recent-events'],
      ],
    );
    await tester.scrollUntilVisible(
      find.text('Related Pages'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('About Me'), findsOneWidget);
    expect(find.text('Recent Events'), findsOneWidget);
  });

  testWidgets(
      'KnowledgePageDetailPage navigates to the merge target after merging',
      (tester) async {
    final backend = _MergeableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:topics:alpha'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Topic Alpha'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge Pages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Topic Beta'));
    await tester.pumpAndSettle();

    expect(find.text('Topic Beta'), findsWidgets);
  });

  testWidgets('KnowledgePageDetailPage shows final governance sections',
      (tester) async {
    final backend = _KnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Current conclusion'), findsOneWidget);
    expect(find.text('System Judgment'), findsOneWidget);
    expect(find.text('View Evidence'), findsOneWidget);
    expect(find.text('View History'), findsOneWidget);
    expect(find.text('Archive Page'), findsOneWidget);
    expect(find.text('Permanently Remove'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('You May Want to Do'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('You May Want to Do'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Evidence Basis'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Evidence Basis'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Related Pages'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Related Pages'), findsOneWidget);
  });

  testWidgets(
      'KnowledgePageDetailPage evidence summary uses page source count instead of entry count',
      (tester) async {
    final backend = _EvidenceCountKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Evidence Basis'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        '4 source documents currently support this page. Conflicts detected: 1.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('KnowledgePageDetailPage localizes the body field label',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.zhCn);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));

    final backend = _MutableKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('更正当前结论'));
    await tester.pumpAndSettle();

    expect(find.text('正文'), findsOneWidget);
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('KnowledgePageDetailPage keeps removed pages audit-only',
      (tester) async {
    final backend = _RemovedKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Correct current conclusion'), findsNothing);
    expect(find.text('Mark inaccurate'), findsNothing);
    expect(find.text('Stop using in answers'), findsNothing);
    expect(find.text('Use in answers again'), findsNothing);
    expect(find.text('Archive Page'), findsNothing);
    expect(find.text('Permanently Remove'), findsNothing);
    expect(find.text('View Evidence'), findsWidgets);
    expect(find.text('View History'), findsWidgets);
  });

  testWidgets('KnowledgePageDetailPage keeps archived pages audit-only',
      (tester) async {
    final backend = _ArchivedKnowledgePageDetailBackendStub();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const KnowledgePageDetailPage(pageId: 'page:preferences'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Correct current conclusion'), findsNothing);
    expect(find.text('Mark inaccurate'), findsNothing);
    expect(find.text('Stop using in answers'), findsNothing);
    expect(find.text('Use in answers again'), findsNothing);
    expect(find.text('Archive Page'), findsNothing);
    expect(find.text('Permanently Remove'), findsNothing);
    expect(find.text('View Evidence'), findsWidgets);
    expect(find.text('View History'), findsWidgets);
  });
}
