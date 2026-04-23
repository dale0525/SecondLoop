library sync_settings_page_delete_actions_test;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

part 'sync_settings_page_delete_actions_test_support.dart';

void main() {
  testWidgets(
      'sync settings groups delete actions together and removes inline descriptions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    await tester.pumpWidget(
      _wrap(
        backend: _DeleteActionsBackend(),
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    final deleteActionsRow = find.byKey(const ValueKey('sync_delete_actions'));
    await _ensureVisible(tester, deleteActionsRow);

    expect(deleteActionsRow, findsOneWidget);
    expect(
      find.descendant(
        of: deleteActionsRow,
        matching: find.widgetWithText(OutlinedButton, 'Delete local cache'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: deleteActionsRow,
        matching: find.widgetWithText(OutlinedButton, 'Delete local data'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: deleteActionsRow,
        matching: find.widgetWithText(OutlinedButton, 'Delete all data'),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('remote sync storage keeps a copy'),
      findsNothing,
    );
    expect(
      find.textContaining('messages, attachments, and embeddings'),
      findsNothing,
    );
  });

  testWidgets('delete local cache requires confirmation before clearing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend();
    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete local cache');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Delete local cache?'), findsOneWidget);
    expect(
      find.textContaining('re-downloaded on demand'),
      findsOneWidget,
    );
    expect(backend.clearLocalCacheCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.clearLocalCacheCalls, 0);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.clearLocalCacheCalls, 1);
    expect(find.text('Deleted local cache'), findsOneWidget);
  });

  testWidgets(
      'delete all data clears remote and local webdav data after confirmation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend();
    final engine = SyncEngine(
      syncRunner: _NoopSyncRunner(),
      loadConfig: () async => null,
      pullOnStart: false,
    );
    var notifications = 0;
    engine.changes.addListener(() => notifications += 1);

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Delete all data?'), findsOneWidget);
    expect(
      find.textContaining('current sync backend'),
      findsOneWidget,
    );
    expect(backend.syncWebdavClearRemoteRootCalls, 0);
    expect(backend.resetLocalDataCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.syncWebdavClearRemoteRootCalls, 0);
    expect(backend.resetLocalDataCalls, 0);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);
    expect(notifications, 1);
    expect(find.text('Deleted local and remote data'), findsOneWidget);

    engine.stop();
  });

  testWidgets('delete all data uses managed vault clear for cloud backend',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('victim_uid');
    await store.writeManagedVaultBaseUrl('https://saved.example.com');

    final backend = _DeleteActionsBackend();
    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        cloudAuthController: _FakeCloudAuthController(userId: 'victim_uid'),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.syncManagedVaultClearVaultCalls, 1);
    expect(backend.lastManagedVaultClearVaultId, 'victim_uid');
    expect(backend.lastManagedVaultClearBaseUrl, 'https://saved.example.com');
    expect(backend.syncWebdavClearRemoteRootCalls, 0);
    expect(backend.syncLocaldirClearRemoteRootCalls, 0);
    expect(backend.resetLocalDataCalls, 1);
  });

  testWidgets(
      'delete all data blocks managed vault clear when signed-in user mismatches saved vault',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('victim_uid');
    await store.writeManagedVaultBaseUrl('https://saved.example.com');

    final backend = _DeleteActionsBackend();
    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        cloudAuthController: _FakeCloudAuthController(userId: 'other_uid'),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.syncManagedVaultClearVaultCalls, 0);
    expect(backend.resetLocalDataCalls, 0);
    expect(find.textContaining('Delete failed:'), findsOneWidget);
  });

  testWidgets(
      'delete all data ignores unsaved managed vault endpoint override edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('victim_uid');
    await store.writeManagedVaultBaseUrl('https://saved.example.com');

    final backend = _DeleteActionsBackend();
    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        cloudAuthController: _FakeCloudAuthController(userId: 'victim_uid'),
      ),
    );
    await tester.pumpAndSettle();

    final syncMethodTitle = find.text('Sync method').first;
    await _ensureVisible(tester, syncMethodTitle);
    await tester.longPress(syncMethodTitle);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Cloud server address (advanced)'),
      'https://unsaved.example.com',
    );

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.syncManagedVaultClearVaultCalls, 1);
    expect(backend.lastManagedVaultClearBaseUrl, 'https://saved.example.com');
  });

  testWidgets('delete all data stops sync engine before remote clear completes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final remoteClearCompleter = Completer<void>();
    final backend = _DeleteActionsBackend(
      webdavClearRemoteRootCompleter: remoteClearCompleter,
    );
    final runner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 0);

    remoteClearCompleter.complete();
    await tester.pumpAndSettle();

    engine.stop();
  });

  testWidgets('delete all data hard-stops pending pushes before remote clear',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final remoteClearCompleter = Completer<void>();
    final backend = _DeleteActionsBackend(
      webdavClearRemoteRootCompleter: remoteClearCompleter,
    );
    final runner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: const Duration(days: 1),
    )..start();
    engine.notifyLocalMutation();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 0);

    remoteClearCompleter.complete();
    await tester.pumpAndSettle();

    engine.stop();
  });

  testWidgets('delete all data waits for in-flight push before remote clear',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final runner = _BlockingPushRunner();
    final backend = _DeleteActionsBackend();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    engine.triggerPushNow();
    await runner.pushStarted.future;

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();

    expect(backend.syncWebdavClearRemoteRootCalls, 0);
    expect(backend.resetLocalDataCalls, 0);

    runner.completePush();
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);

    engine.stop();
  });

  testWidgets(
      'delete all data uses saved sync config instead of unsaved form edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SavedRoot');
    await store.writeWebdavBaseUrl('https://saved.example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend();
    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Server address'),
      'https://unsaved.example.com/dav',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Folder name'),
      'UnsavedRoot',
    );

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.lastWebdavClearBaseUrl, 'https://saved.example.com/dav');
    expect(backend.lastWebdavClearRemoteRoot, 'SavedRoot');
    expect(backend.resetLocalDataCalls, 1);
  });

  testWidgets('delete all data restarts sync engine after success',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend();
    final runner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(engine.isRunning, isTrue);

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 1);

    engine.stop();
  });

  testWidgets(
      'delete all data does not start sync engine when it was already stopped',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend();
    final runner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    );

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(engine.isRunning, isFalse);

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 0);
  });

  testWidgets('delete all data restarts sync engine after remote clear failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend(
      webdavClearRemoteRootError: StateError('remote clear failed'),
    );
    final runner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.webdav(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        remoteRoot: 'SecondLoop',
        baseUrl: 'https://example.com/dav',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.resetLocalDataCalls, 0);
    expect(find.textContaining('Delete failed:'), findsOneWidget);

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 1);

    engine.stop();
  });

  testWidgets('delete all data keeps deleting local data after remote timeout',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend(
      webdavClearRemoteRootError: TimeoutException('operation timeout'),
    );

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);
    expect(find.textContaining('Deleted local data only'), findsOneWidget);
    expect(find.textContaining('remote clear timed out'), findsOneWidget);
  });

  testWidgets(
      'cloud session model persists canonical managed vault config on load',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    await tester.pumpWidget(
      _wrap(
        backend: _DeleteActionsBackend(),
        store: store,
        cloudAuthController: _FakeCloudAuthController(),
        capabilities: AppPlatformCapabilities.webCloud(),
      ),
    );
    await tester.pumpAndSettle();

    final configured = await store.loadConfiguredSync();
    expect(configured, isNotNull);
    expect(configured!.backendType, SyncBackendType.managedVault);
    expect(configured.remoteRoot, 'uid_1');
    expect(configured.baseUrl, 'https://vault.default.example');
  });
}
