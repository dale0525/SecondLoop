library sync_settings_page_delete_actions_test;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

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
part 'sync_settings_page_delete_actions_regression_part.dart';
part 'sync_settings_page_delete_actions_tail_part.dart';

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

    expect(find.text('Delete local cache again?'), findsOneWidget);
    expect(
      find.textContaining('Cached files from this device'),
      findsOneWidget,
    );
    expect(backend.clearLocalCacheCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.clearLocalCacheCalls, 0);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.clearLocalCacheCalls, 1);
    expect(find.text('Deleted local cache'), findsOneWidget);
  });

  testWidgets(
      'delete local data requires a second confirmation before clearing',
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

    final button = find.widgetWithText(OutlinedButton, 'Delete local data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Delete local data?'), findsOneWidget);
    expect(
      find.textContaining('messages, attachments, and embeddings'),
      findsOneWidget,
    );
    expect(backend.resetLocalDataCalls, 0);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete local data again?'), findsOneWidget);
    expect(
      find.textContaining('remote copy is not changed'),
      findsOneWidget,
    );
    expect(backend.resetLocalDataCalls, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.resetLocalDataCalls, 0);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.resetLocalDataCalls, 1);
    expect(find.text('Local synced data deleted'), findsOneWidget);
  });

  testWidgets('delete local data shows progress while deletion is running',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final resetCompleter = Completer<void>();
    final backend = _DeleteActionsBackend(
      resetLocalDataCompleter: resetCompleter,
    );
    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete local data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pump();

    expect(find.text('Deleting…'), findsOneWidget);
    expect(find.text('Deleting local synced data…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    resetCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Deleting…'), findsNothing);
    expect(find.text('Deleting local synced data…'), findsNothing);
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

    expect(find.text('Delete all data again?'), findsOneWidget);
    expect(
      find.textContaining('This also clears the remote sync data'),
      findsOneWidget,
    );
    expect(backend.syncWebdavClearRemoteRootCalls, 0);
    expect(backend.resetLocalDataCalls, 0);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);
    expect(notifications, 1);
    expect(find.text('Deleted local and remote data'), findsOneWidget);

    engine.stop();
  });

  testWidgets(
      'delete all data supports legacy webdav config without sync_backend_type',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SyncConfigStore.prefsBlobKeyForTest: jsonEncode({
        SyncConfigStore.kRemoteRoot: 'SecondLoop',
        SyncConfigStore.kWebdavBaseUrl: 'https://example.com/dav',
      }),
    });
    final store = SyncConfigStore();
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend();
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
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.lastWebdavClearBaseUrl, 'https://example.com/dav');
    expect(backend.lastWebdavClearRemoteRoot, 'SecondLoop');
    expect(backend.resetLocalDataCalls, 1);
    expect(find.text('Deleted local and remote data'), findsOneWidget);
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
    await _confirmDeletionTwice(tester);
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
    await _confirmDeletionTwice(tester);
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
    await _confirmDeletionTwice(tester);
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
    await _confirmDeletionTwice(tester);
    await tester.pump();

    expect(find.text('Deleting…'), findsOneWidget);
    expect(find.text('Deleting local and remote data…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 0);

    remoteClearCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('Deleting…'), findsNothing);
    expect(find.text('Deleting local and remote data…'), findsNothing);

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
    await _confirmDeletionTwice(tester);
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
    await _confirmDeletionTwice(tester);
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
      'delete all data waits for draining push after engine entered stop-after-drain',
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
      pushDebounce: const Duration(days: 1),
    )..start();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
      ),
    );
    await tester.pumpAndSettle();

    engine.notifyLocalMutation();
    await tester.pump();
    engine.stop();
    await runner.pushStarted.future;

    expect(engine.isRunning, isFalse);

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pump();

    expect(backend.syncWebdavClearRemoteRootCalls, 0);
    expect(backend.resetLocalDataCalls, 0);

    runner.completePush();
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);
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
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.lastWebdavClearBaseUrl, 'https://saved.example.com/dav');
    expect(backend.lastWebdavClearRemoteRoot, 'SavedRoot');
    expect(backend.resetLocalDataCalls, 1);
  });

  testWidgets(
      'delete all data disables auto sync and keeps sync engine stopped',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeAutoEnabled(true);

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
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);
    expect(await store.readAutoEnabled(), isFalse);
    expect(engine.isRunning, isFalse);
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
    await _confirmDeletionTwice(tester);
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
    await _confirmDeletionTwice(tester);
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
    await store.writeAutoEnabled(true);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend(
      webdavClearRemoteRootError: TimeoutException('operation timeout'),
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
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(backend.syncWebdavClearRemoteRootCalls, 1);
    expect(backend.resetLocalDataCalls, 1);
    expect(await store.readAutoEnabled(), isFalse);
    expect(engine.isRunning, isFalse);
    expect(find.textContaining('Deleted local data only'), findsOneWidget);
    expect(find.textContaining('remote clear timed out'), findsOneWidget);

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 0);
  });

  testWidgets(
      'delete all data clears managed vault local repair gate before staying stopped',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _DeleteActionsBackend();
    final runner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => SyncConfig.managedVault(
        syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
        vaultId: 'uid_1',
        baseUrl: 'https://vault.default.example',
      ),
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();
    engine.writeGate.value = const SyncWriteGateState.localRepairRequired();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        engine: engine,
        cloudAuthController: _FakeCloudAuthController(),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.widgetWithText(OutlinedButton, 'Delete all data');
    await _ensureVisible(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _confirmDeletionTwice(tester);
    await tester.pumpAndSettle();

    expect(engine.isRunning, isFalse);
    expect(engine.writeGate.value.kind, SyncWriteGateKind.open);

    engine.triggerPushNow();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(runner.pushCalls, 0);
  });

  registerDeleteActionsTailTests();
  registerDeleteActionsRegressionTests();
}
