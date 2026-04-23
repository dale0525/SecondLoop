import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

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
    await store.writeManagedVaultBaseUrl('https://cloud.example.com');

    final backend = _DeleteActionsBackend();
    await tester.pumpWidget(
      _wrap(
        backend: backend,
        store: store,
        cloudAuthController: _FakeCloudAuthController(),
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
    expect(backend.lastManagedVaultClearVaultId, 'uid_1');
    expect(backend.syncWebdavClearRemoteRootCalls, 0);
    expect(backend.syncLocaldirClearRemoteRootCalls, 0);
    expect(backend.resetLocalDataCalls, 1);
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
}

Widget _wrap({
  required AppBackend backend,
  required SyncConfigStore store,
  SyncEngine? engine,
  CloudAuthController? cloudAuthController,
}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: CloudAuthScope(
          controller: cloudAuthController ?? _FakeCloudAuthController(),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: SyncEngineScope(
              engine: engine,
              child: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _ensureVisible(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  try {
    await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
  } catch (_) {
    await tester.scrollUntilVisible(target, -180, scrollable: scrollable);
  }
  await tester.pumpAndSettle();
}

final class _DeleteActionsBackend extends AppBackend {
  _DeleteActionsBackend({
    this.webdavClearRemoteRootError,
    this.webdavClearRemoteRootCompleter,
  });

  int clearLocalCacheCalls = 0;
  int resetLocalDataCalls = 0;
  int syncWebdavClearRemoteRootCalls = 0;
  int syncLocaldirClearRemoteRootCalls = 0;
  int syncManagedVaultClearVaultCalls = 0;
  String? lastManagedVaultClearVaultId;
  String? lastWebdavClearBaseUrl;
  String? lastWebdavClearRemoteRoot;
  final Object? webdavClearRemoteRootError;
  final Completer<void>? webdavClearRemoteRootCompleter;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => null;

  @override
  Future<void> saveSessionKey(Uint8List key) async {}

  @override
  Future<void> clearSavedSessionKey() async {}

  @override
  Future<void> validateKey(Uint8List key) async {}

  @override
  Future<Uint8List> initMasterPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<Uint8List> unlockWithPassword(String password) async =>
      Uint8List.fromList(List<int>.filled(32, 1));

  @override
  Future<List<Conversation>> listConversations(Uint8List key) async =>
      const <Conversation>[];

  @override
  Future<Conversation> createConversation(Uint8List key, String title) async =>
      throw UnimplementedError();

  @override
  Future<Conversation> getOrCreateLoopHomeConversation(Uint8List key) async =>
      throw UnimplementedError();

  @override
  Future<List<Message>> listMessages(
    Uint8List key,
    String conversationId,
  ) async =>
      const <Message>[];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> editMessage(
    Uint8List key,
    String messageId,
    String content,
  ) async =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
    Uint8List key,
    String messageId,
    bool isDeleted,
  ) async =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    resetLocalDataCalls += 1;
  }

  @override
  Future<void> clearLocalAttachmentCache(Uint8List key) async {
    clearLocalCacheCalls += 1;
  }

  @override
  Future<String> getOrCreateDeviceId() async => 'device-1';

  @override
  Future<int> processPendingMessageEmbeddings(
    Uint8List key, {
    int limit = 32,
  }) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(
    Uint8List key, {
    int batchLimit = 256,
  }) async =>
      0;

  @override
  Future<List<String>> listEmbeddingModelNames(Uint8List key) async =>
      const <String>['secondloop-default-embed-v0'];

  @override
  Future<String> getActiveEmbeddingModelName(Uint8List key) async =>
      'secondloop-default-embed-v0';

  @override
  Future<bool> setActiveEmbeddingModelName(Uint8List key, String modelName) =>
      Future<bool>.value(modelName != 'secondloop-default-embed-v0');

  @override
  Future<List<LlmProfile>> listLlmProfiles(Uint8List key) async =>
      const <LlmProfile>[];

  @override
  Future<LlmProfile> createLlmProfile(
    Uint8List key, {
    required String name,
    required String providerType,
    String? baseUrl,
    String? apiKey,
    required String modelName,
    bool setActive = true,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> setActiveLlmProfile(Uint8List key, String profileId) async {}

  @override
  Future<void> deleteLlmProfile(Uint8List key, String profileId) async {}

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) =>
      const Stream<String>.empty();

  @override
  Stream<String> askAiStreamCloudGateway(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
    required String gatewayBaseUrl,
    required String idToken,
    required String modelName,
  }) =>
      const Stream<String>.empty();

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 9));

  @override
  Future<Uint8List> recoverSyncKeyFromEnvelope(
    String envelopeJson,
    String passphrase,
  ) async =>
      Uint8List.fromList(List<int>.filled(32, 6));

  @override
  Future<String> createSyncRecoveryEnvelope(
    Uint8List syncKey,
    String passphrase,
  ) async =>
      '{"version":1,"wrapped_sync_key_b64":"local","kdf":{"version":1}}';

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    syncWebdavClearRemoteRootCalls += 1;
    lastWebdavClearBaseUrl = baseUrl;
    lastWebdavClearRemoteRoot = remoteRoot;
    final completer = webdavClearRemoteRootCompleter;
    if (completer != null) {
      await completer.future;
    }
    final error = webdavClearRemoteRootError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<void> syncLocaldirTestConnection({
    required String localDir,
    required String remoteRoot,
  }) async {}

  @override
  Future<void> syncLocaldirClearRemoteRoot({
    required String localDir,
    required String remoteRoot,
  }) async {
    syncLocaldirClearRemoteRootCalls += 1;
  }

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      0;

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async =>
      0;

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async =>
      0;

  @override
  Future<void> syncManagedVaultClearVault({
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    syncManagedVaultClearVaultCalls += 1;
    lastManagedVaultClearVaultId = vaultId;
  }
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> push(SyncConfig config) async => 0;

  @override
  Future<int> pull(SyncConfig config) async => 0;
}

final class _CountingSyncRunner implements SyncRunner {
  int pushCalls = 0;

  @override
  Future<int> push(SyncConfig config) async {
    pushCalls += 1;
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) async => 0;
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  Future<String?> getIdToken() async => 'test-id-token';

  @override
  String? get uid => 'uid_1';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
