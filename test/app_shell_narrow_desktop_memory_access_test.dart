import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/app/router.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/knowledge_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/update/update_badge_prefs.dart';
import 'package:secondloop/src/rust/knowledge/models.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateBadgePrefs.resetForTests();
  });

  testWidgets('narrow desktop AppShell still exposes Memory navigation',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      await tester.binding.setSurfaceSize(const Size(700, 900));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: TestAppBackend(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AppShell(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('app_shell_bottom_nav')), findsOneWidget);

      await tester.tap(find.text('Memory'));
      await tester.pumpAndSettle();

      expect(find.text('Memory'), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('narrow desktop AppShell lazy loads Memory tab content',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final backend = _CountingKnowledgeBackend();

    try {
      await tester.binding.setSurfaceSize(const Size(700, 900));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AppShell(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(backend.listKnowledgeDocumentsCalls, 0);

      await tester.tap(find.text('Memory'));
      await tester.pumpAndSettle();

      expect(backend.listKnowledgeDocumentsCalls, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('narrow desktop AppShell preserves settings update badge',
      (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      UpdateBadgePrefs.value.value = 'v1.2.3';
      await tester.binding.setSurfaceSize(const Size(700, 900));

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: TestAppBackend(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const AppShell(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app_tab_settings_update_badge_bottom_nav')),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
      UpdateBadgePrefs.resetForTests();
      await tester.binding.setSurfaceSize(null);
    }
  });
}

final class _CountingKnowledgeBackend extends TestAppBackend
    implements KnowledgeBackend {
  int listKnowledgeDocumentsCalls = 0;

  @override
  Future<KnowledgeIndexStatus> getKnowledgeIndexStatus(Uint8List key) {
    throw UnimplementedError();
  }

  @override
  Future<KnowledgeDebugStats> getKnowledgeDebugStats(Uint8List key) {
    throw UnimplementedError();
  }

  @override
  Future<void> requestKnowledgeRebuild(Uint8List key) {
    throw UnimplementedError();
  }

  @override
  Future<int> processPendingKnowledgeIndexJobs(
    Uint8List key, {
    int limit = 32,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cancelKnowledgeRebuild(Uint8List key) {
    throw UnimplementedError();
  }

  @override
  Future<List<ContentKnowledgeDocument>> listKnowledgeDocuments(
    Uint8List key, {
    int limit = 100,
    int offset = 0,
  }) async {
    listKnowledgeDocumentsCalls += 1;
    return const <ContentKnowledgeDocument>[];
  }

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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<KnowledgeUnit>> listKnowledgeUnits(
    Uint8List key, {
    required String documentId,
    KnowledgeUnitKind? unitKind,
    int limit = 100,
    int offset = 0,
  }) {
    throw UnimplementedError();
  }
}
