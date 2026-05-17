import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/core/models/app_models.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('managed vault sync settings shows zero media upload stats',
      (tester) async {
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('en'),
          home: AppBackendScope(
            backend: _SummaryBackend(
              const CloudMediaBackupSummary(
                pending: 0,
                failed: 0,
                uploaded: 0,
              ),
            ),
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('sync_media_backup_enabled')),
    );

    expect(find.text('Queued 0 · Failed 0 · Uploaded 0'), findsOneWidget);
    expect(find.textContaining('missing_local_attachment_bytes'), findsNothing);
  });

  testWidgets('backfill refreshes media summary for the edited scope',
      (tester) async {
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 3));
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeWebdavBaseUrl('https://dav-a.example.com');
    await store.writeWebdavUsername('user-a');
    await store.writeRemoteRoot('root-a');
    await store.writeSyncKey(syncKey);

    final scopeA = store.syncStateScopeId(
      SyncConfig.webdav(
        syncKey: syncKey,
        remoteRoot: 'root-a',
        baseUrl: 'https://dav-a.example.com',
        username: 'user-a',
        password: null,
      ),
    );
    final scopeB = store.syncStateScopeId(
      SyncConfig.webdav(
        syncKey: syncKey,
        remoteRoot: 'root-b',
        baseUrl: 'https://dav-b.example.com',
        username: 'user-b',
        password: null,
      ),
    );
    final backend = _ScopedSummaryBackend(
      summaries: <String, CloudMediaBackupSummary>{
        scopeA: const CloudMediaBackupSummary(
          pending: 1,
          failed: 0,
          uploaded: 0,
        ),
        scopeB: const CloudMediaBackupSummary(
          pending: 4,
          failed: 0,
          uploaded: 2,
        ),
      },
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('en'),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.byType(TextField).at(0), 'https://dav-b.example.com');
    await tester.enterText(find.byType(TextField).at(1), 'user-b');
    await tester.enterText(find.byType(TextField).at(3), 'root-b');
    await tester.pump();

    await _ensureVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Queue existing files'),
    );
    await tester
        .tap(find.widgetWithText(OutlinedButton, 'Queue existing files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(backend.backfillScopeIds.last, scopeB);
    expect(backend.summaryScopeIds.last, scopeB);
    expect(find.text('Queued 4 · Failed 0 · Uploaded 2'), findsOneWidget);
  });
}

Future<void> _ensureVisible(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  try {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: scrollable,
    );
  } catch (_) {
    await tester.scrollUntilVisible(
      target,
      -180,
      scrollable: scrollable,
    );
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

final class _SummaryBackend extends AppBackend {
  _SummaryBackend(this.summary);

  final CloudMediaBackupSummary summary;

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) async {
    return summary;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ScopedSummaryBackend extends AppBackend {
  _ScopedSummaryBackend({
    required this.summaries,
  });

  final Map<String, CloudMediaBackupSummary> summaries;
  final List<String?> summaryScopeIds = <String?>[];
  final List<String?> backfillScopeIds = <String?>[];

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
    String? scopeId,
  }) async {
    backfillScopeIds.add(scopeId);
    return 3;
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) async {
    summaryScopeIds.add(scopeId);
    return summaries[scopeId] ??
        const CloudMediaBackupSummary(
          pending: 0,
          failed: 0,
          uploaded: 0,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
