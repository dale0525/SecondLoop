import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/backend/knowledge_viewer_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/memory/memory_center_page.dart';
import 'package:secondloop/features/memory/memory_center_models.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('MemoryCenterPage groups generated memory cards', (tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _MemoryBackend(
      documents: [
        _document(
          documentId: 'generated:preference:response-language',
          title: 'Response language',
          summary: 'User prefers Chinese.\nUse concise bullets.',
          updatedAtMs: nowMs,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.preference,
            sourceCount: 2,
            status: KnowledgeMemoryStatus.inferred,
          ),
        ),
        _document(
          documentId: 'generated:event:trip-plan',
          title: 'Trip plan',
          summary: 'Upcoming trip to Shanghai.',
          updatedAtMs: nowMs - const Duration(days: 2).inMilliseconds,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.recentEvent,
            sourceCount: 1,
            status: KnowledgeMemoryStatus.inferred,
          ),
        ),
        _document(
          documentId: 'generated:profile:launch-work',
          title: 'Launch work',
          summary:
              'Working on project launch checklist.\nPreparing rollout notes.',
          updatedAtMs: nowMs,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.project,
            sourceCount: 2,
            status: KnowledgeMemoryStatus.inferred,
          ),
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

    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Recent events'), findsOneWidget);
    expect(find.text('Response language'), findsOneWidget);
    expect(find.text('Trip plan'), findsOneWidget);
    expect(find.text('Launch work'), findsOneWidget);
    expect(find.textContaining('2 sources'), findsWidgets);
    expect(find.textContaining('Updated today'), findsWidgets);
  });

  test(
      'buildMemoryCenterSections localizes generated memory titles and summaries',
      () {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final sections = buildMemoryCenterSections(
      [
        _document(
          documentId: 'generated:pattern:active-task-focus',
          title: 'Active task pattern',
          summary: 'User is actively working across these task threads:',
          rawText:
              'User is actively working across these task threads:\n- 做视频 [in_progress]\n- 复盘选题 [open]',
          updatedAtMs: nowMs,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.project,
            sourceCount: 2,
            status: KnowledgeMemoryStatus.inferred,
          ),
        ),
      ],
      AppLocale.zhCn.build(),
    );

    expect(sections.single.cards.single.title, '当前任务模式');
    expect(sections.single.cards.single.summary, '用户当前主要在推进这些任务：');
  });

  testWidgets(
    'MemoryCenterPage paginates until generated memories are found beyond the first page',
    (tester) async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final backend = _MemoryBackend(
        documents: [
          for (var index = 0; index < 205; index += 1)
            _document(
              documentId: 'message:seed-$index',
              title: 'Source $index',
              summary: 'Non-memory source document.',
              updatedAtMs: nowMs - index,
              originType: KnowledgeOriginType.message,
            ),
          _document(
            documentId: 'generated:preference:response-language',
            title: 'Response language',
            summary: 'User prefers Chinese.',
            updatedAtMs: nowMs - 10000,
            memoryDisplay: const KnowledgeMemoryDisplay(
              section: KnowledgeMemorySection.preference,
              sourceCount: 2,
              status: KnowledgeMemoryStatus.inferred,
            ),
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

      expect(find.text('Response language'), findsOneWidget);
      expect(backend.listOffsets, containsAllInOrder(<int>[0, 200]));
    },
  );

  testWidgets('MemoryCenterPage uses backend-native section metadata', (
    tester,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _MemoryBackend(
      documents: [
        _document(
          documentId: 'generated:profile:release-companion',
          title: 'Release companion',
          summary: 'Shared launch coordination memory.',
          updatedAtMs: nowMs,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.project,
            sourceCount: 4,
            status: KnowledgeMemoryStatus.confirmed,
          ),
        ),
        _document(
          documentId: 'generated:pattern:weekly-focus',
          title: 'Weekly focus',
          summary: 'Recurring planning topic.',
          updatedAtMs: nowMs - const Duration(days: 3).inMilliseconds,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.topic,
            sourceCount: 3,
            status: KnowledgeMemoryStatus.maybeOutdated,
          ),
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

    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Topics'), findsOneWidget);
    expect(find.text('Release companion'), findsOneWidget);
    expect(find.text('Weekly focus'), findsOneWidget);
    expect(find.textContaining('4 sources'), findsOneWidget);
    expect(find.textContaining('Confirmed'), findsOneWidget);
    expect(find.textContaining('Maybe outdated'), findsOneWidget);
  });

  testWidgets('MemoryCenterPage does not reload on an unrelated parent rebuild',
      (
    tester,
  ) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final backend = _MemoryBackend(
      documents: [
        _document(
          documentId: 'generated:preference:response-language',
          title: 'Response language',
          summary: 'User prefers Chinese.',
          updatedAtMs: nowMs,
          memoryDisplay: const KnowledgeMemoryDisplay(
            section: KnowledgeMemorySection.preference,
            sourceCount: 1,
            status: KnowledgeMemoryStatus.inferred,
          ),
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
    expect(backend.listOffsets, <int>[0]);

    await tester
        .tap(find.byKey(const ValueKey('memory_center_harness_rebuild')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      backend.listOffsets,
      <int>[0],
      reason: 'parent rebuilds should reuse the cached load future',
    );
  });
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

final class _MemoryBackend extends TestAppBackend
    implements KnowledgeBackend, KnowledgeViewerBackend {
  _MemoryBackend({required this.documents});

  final List<ContentKnowledgeDocument> documents;
  final List<int> listOffsets = <int>[];

  @override
  Future<KnowledgeMemoryFeedback> upsertKnowledgeMemoryFeedback(
    Uint8List key, {
    required String documentId,
    KnowledgeMemoryStatus? status,
    required bool useForAskAi,
    required bool isDeleted,
    required bool markedInaccurate,
    String? correctedTitle,
    String? correctedSummary,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> cancelKnowledgeRebuild(Uint8List key) async {}

  @override
  Future<KnowledgeDebugStats> getKnowledgeDebugStats(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<KnowledgeViewerDocument> getKnowledgeViewerDocument(
    Uint8List key, {
    required String documentId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) async {
    listOffsets.add(offset);
    return documents.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async =>
      const <KnowledgeUnit>[];

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnitsAroundAnchor(
    Uint8List key, {
    required String documentId,
    required KnowledgeAnchorSet anchor,
    int before = 2,
    int after = 3,
  }) async =>
      const <KnowledgeUnit>[];

  @override
  Future<KnowledgeViewerPage> listKnowledgeViewerUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) async =>
      throw UnimplementedError();

  @override
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 8,
  }) async =>
      0;

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) async {}

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledge(
    Uint8List key, {
    required String query,
    String? conversationId,
    String? documentId,
    int limit = 20,
  }) async =>
      const <KnowledgeSearchResult>[];

  @override
  Future<List<KnowledgeSearchResult>> searchKnowledgeDocumentUnits(
    Uint8List key, {
    required String documentId,
    required String query,
    int limit = 20,
  }) async =>
      const <KnowledgeSearchResult>[];
}

ContentKnowledgeDocument _document({
  required String documentId,
  required String title,
  required String summary,
  required int updatedAtMs,
  String? rawText,
  KnowledgeOriginType originType = KnowledgeOriginType.generated,
  KnowledgeMemoryDisplay? memoryDisplay,
}) {
  return ContentKnowledgeDocument(
    documentId: documentId,
    originType: originType,
    sourceKind: KnowledgeSourceKind.summary,
    role: KnowledgeRole.summary,
    language: 'en',
    qualityScore: 1,
    createdAtMs: 1,
    updatedAtMs: updatedAtMs,
    versions: const KnowledgeVersionSet(
      schemaVersion: 1,
      normalizationVersion: 1,
      segmentationVersion: 1,
      embeddingPolicyVersion: 1,
      retrievalPolicyVersion: 1,
    ),
    anchors: const KnowledgeAnchorSet(),
    title: title,
    summary: summary,
    rawText: rawText ?? summary,
    normalizedText: rawText ?? summary,
    memoryDisplay: memoryDisplay,
    memoryFeedback: const KnowledgeMemoryFeedback(
      useForAskAi: true,
      isDeleted: false,
      markedInaccurate: false,
    ),
  );
}
