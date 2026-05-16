import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/secretary_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/memory/memory_models.dart';
import 'package:secondloop/features/memory/memory_page.dart';
import 'package:secondloop/src/rust/db.dart';
import 'package:secondloop/src/rust/platform_int.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  Future<void> pumpMemoryPage(
    WidgetTester tester, {
    MemoryDemoData? data,
  }) async {
    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(home: MemoryPage(data: data)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('default MemoryPage does not show demo memories', (tester) async {
    await pumpMemoryPage(tester);

    expect(find.text('No knowledge pages yet.'), findsOneWidget);
    expect(find.text('Morning meeting guardrail'), findsNothing);
    expect(find.text('Alex Chen'), findsNothing);
    expect(find.text('Project Atlas'), findsNothing);
    expect(find.text('passport-scan.pdf'), findsNothing);
  });

  testWidgets('default MemoryPage loads active backend memories',
      (tester) async {
    final backend = _MemoryPageBackend(
      memoryPages: [
        _memoryPage(
          id: 'memory-meeting',
          title: '我上午 9 点前不开会',
          body: '我上午 9 点前不开会',
        ),
        _memoryPage(
          id: 'memory-language',
          title: '任务回复请使用中文',
          body: '任务回复请使用中文',
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
              child: const MemoryPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我上午 9 点前不开会'), findsWidgets);
    expect(find.text('任务回复请使用中文'), findsWidgets);
    expect(find.text('No knowledge pages yet.'), findsNothing);
  });

  testWidgets('Preferences tab shows preferences and one candidate only',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    expect(find.byKey(const ValueKey('memory_side_tab_list')), findsNothing);
    expect(find.text('Morning meeting guardrail'), findsOneWidget);
    expect(find.text('Candidate memory'), findsOneWidget);
    expect(find.text('Alex Chen'), findsNothing);
    expect(find.text('Project Atlas'), findsNothing);
  });

  testWidgets('People tab shows person list and selected person detail',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('memory_side_tab_list')), findsNothing);
    expect(find.text('Alex Chen'), findsOneWidget);
    expect(find.text('Selected person detail'), findsOneWidget);
    expect(find.text('Morning meeting guardrail'), findsNothing);
    expect(find.text('Project Atlas'), findsNothing);
  });

  testWidgets('Projects tab shows project list and selected project detail',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();

    expect(find.text('Project Atlas'), findsOneWidget);
    expect(find.text('Selected project detail'), findsOneWidget);
    expect(find.text('Alex Chen'), findsNothing);
    expect(find.text('Source snippets'), findsNothing);
  });

  testWidgets('Sources tab shows source list and snippets only',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();

    expect(find.text('passport-scan.pdf'), findsOneWidget);
    expect(find.text('Source snippets'), findsOneWidget);
    expect(find.text('Project Atlas'), findsNothing);
    expect(find.text('Grouped candidates'), findsNothing);
  });

  testWidgets('Suggestions tab shows grouped candidates and actions',
      (tester) async {
    await pumpMemoryPage(tester, data: MemoryDemoData.demo());

    await tester.tap(find.text('Suggestions'));
    await tester.pumpAndSettle();

    expect(find.text('Grouped candidates'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
    expect(find.text('passport-scan.pdf'), findsNothing);
  });
}

final class _MemoryPageBackend extends TestAppBackend
    implements SecretaryBackend {
  _MemoryPageBackend({required List<MemoryPageRecord> memoryPages})
      : _memoryPages = memoryPages;

  final List<MemoryPageRecord> _memoryPages;

  @override
  Future<List<MemoryPageRecord>> listMemoryPages(
    Uint8List key, {
    String? state,
  }) async {
    return _memoryPages
        .where((page) => state == null || page.state == state)
        .toList(growable: false);
  }

  @override
  Future<SecretaryMemoryProposalRecord> createSecretaryMemoryProposal(
    Uint8List key, {
    String? sourceMessageId,
    required String kind,
    required String title,
    required String body,
    required double confidence,
    String? sourceRefsJson,
    String? actionHint,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<SecretaryMemoryProposalRecord>> listSecretaryMemoryProposals(
    Uint8List key, {
    String? state,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> acceptSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SecretaryMemoryProposalRecord> dismissSecretaryMemoryProposal(
    Uint8List key, {
    required String proposalId,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> getMemoryPage(
    Uint8List key, {
    required String pageId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> correctMemoryPage(
    Uint8List key, {
    required String pageId,
    required String title,
    required String summary,
    required String body,
    String? reason,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> archiveMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MemoryPageRecord> restoreMemoryPage(
    Uint8List key, {
    required String pageId,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PlanningOutputRecord> upsertPlanningOutput(
    Uint8List key, {
    required String id,
    required String kind,
    required String title,
    required String body,
    required String itemsJson,
    String? sourceRefsJson,
    required String route,
    required String state,
    required int createdAtMs,
    required int updatedAtMs,
    int? expiresAtMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<PlanningOutputRecord>> listPlanningOutputs(
    Uint8List key, {
    String? kind,
    required int nowMs,
    bool includeExpired = false,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SecretaryRunRecord> createSecretaryRun(
    Uint8List key, {
    required String triggerKind,
    required String route,
    required String status,
    String? inputSummary,
    String? outputSummary,
    String? error,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SecretaryToolCallRecord> createSecretaryToolCall(
    Uint8List key, {
    required String runId,
    required String toolName,
    required String status,
    required bool requiresConfirmation,
    String? inputJson,
    String? outputJson,
    required int nowMs,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<SecretaryToolCallRecord>> listSecretaryToolCallsForRun(
    Uint8List key, {
    required String runId,
  }) async {
    throw UnimplementedError();
  }
}

MemoryPageRecord _memoryPage({
  required String id,
  required String title,
  required String body,
}) {
  return MemoryPageRecord(
    pageId: id,
    pageType: 'memory',
    state: 'active',
    sourceCount: platformIntFromInt(1),
    title: title,
    summary: body,
    body: body,
    primaryEvidenceJson: '[]',
    sourceDocumentIdsJson: '[]',
    confidenceLevel: 0.9,
    humanCorrected: false,
    createdAtMs: platformIntFromInt(1000),
    updatedAtMs: platformIntFromInt(1000),
  );
}
