import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/cloud_sync_switch_prompt_gate.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets(
      'Entitled subscription prompts switching to SecondLoop Cloud sync',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.unknown);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            child: SubscriptionScope(
              controller: subscription,
              child: CloudSyncSwitchPromptGate(
                configStore: store,
                child: const Scaffold(body: Text('home')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);

    subscription.setStatus(SubscriptionStatus.entitled);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Already-entitled subscription prompts immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: CloudAuthScope(
            controller: cloudAuth,
            child: SubscriptionScope(
              controller: subscription,
              child: CloudSyncSwitchPromptGate(
                configStore: store,
                child: const Scaffold(body: Text('home')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Prompt works when gate is above Navigator (MaterialApp.builder)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    final navigatorKey = GlobalKey<NavigatorState>();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.unknown);

    await tester.pumpWidget(
      wrapWithI18n(
        CloudAuthScope(
          controller: cloudAuth,
          child: SubscriptionScope(
            controller: subscription,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: const Scaffold(body: Text('home')),
              builder: (context, child) {
                return CloudSyncSwitchPromptGate(
                  navigatorKey: navigatorKey,
                  configStore: store,
                  child: child ?? const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);

    subscription.setStatus(SubscriptionStatus.entitled);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Switching to Cloud derives managed vault sync key from uid',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    final backend = _Backend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.unknown);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              child: SubscriptionScope(
                controller: subscription,
                child: CloudSyncSwitchPromptGate(
                  configStore: store,
                  child: const Scaffold(body: Text('home')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    subscription.setStatus(SubscriptionStatus.entitled);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(await store.readRemoteRoot(), 'uid_1');
    final syncKey = await store.readSyncKey();
    expect(syncKey, isNotNull);
    expect(syncKey, Uint8List.fromList(List<int>.filled(32, 9)));
    expect(find.text('Enter your recovery passphrase and tap Save first.'),
        findsNothing);
  });

  testWidgets(
      'Cloud sync switch prompt continues to a single AI feature guide prompt and can open AI settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      // Can be set by previous Ask AI / settings interactions.
      'embeddings_data_consent_v1': false,
    });
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);

    final navigatorKey = GlobalKey<NavigatorState>();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('home')),
          builder: (context, child) {
            return CloudAuthScope(
              controller: cloudAuth,
              child: SubscriptionScope(
                controller: subscription,
                child: CloudSyncSwitchPromptGate(
                  navigatorKey: navigatorKey,
                  configStore: store,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('More AI features are now available'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AiSettingsPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai_settings_home_smart_organization')),
      findsOneWidget,
    );
  });

  testWidgets(
      'Switching to Cloud runs push before pull and shows progress first',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      // Consent should still be prompted after the sync completes.
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _SuccessfulPushBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: cloudAuth,
                child: SubscriptionScope(
                  controller: subscription,
                  child: CloudSyncSwitchPromptGate(
                    configStore: store,
                    child: const Scaffold(body: Text('home')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch prompt shows first.
    expect(find.text('Switch'), findsOneWidget);
    await tester.tap(find.text('Switch'));

    // Sync progress dialog appears before the AI guide prompt.
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('cloud_sync_switch_progress')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cloud_sync_switch_progress_percent')),
      findsOneWidget,
    );
    expect(
      find.text('More AI features are now available'),
      findsNothing,
    );

    // After sync finishes, the AI guide prompt appears.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>['syncManagedVaultPush', 'syncManagedVaultPull'],
    );
    expect(find.text('More AI features are now available'), findsOneWidget);
  });

  testWidgets(
      'Switching to Cloud falls back to engine push/pull when progress sync fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _FailingPullBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
    final syncRunner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: syncRunner,
      loadConfig: () async => SyncConfig.managedVault(
        syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
        vaultId: 'uid_1',
        baseUrl: 'https://vault.example.com',
      ),
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );
    engine.start();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: CloudAuthScope(
                  controller: cloudAuth,
                  child: SubscriptionScope(
                    controller: subscription,
                    child: CloudSyncSwitchPromptGate(
                      configStore: store,
                      child: const Scaffold(body: Text('home')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('syncManagedVaultPull'));
    expect(syncRunner.pullCalls, 1);
    expect(syncRunner.pushCalls, 1);

    engine.stop();
  });

  testWidgets('Switching to Cloud still pulls when push is read-only blocked',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _GraceReadOnlyPushBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
    final engine = SyncEngine(
      syncRunner: _CountingSyncRunner(),
      loadConfig: () async => SyncConfig.managedVault(
        syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
        vaultId: 'uid_1',
        baseUrl: 'https://vault.example.com',
      ),
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );
    engine.start();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: CloudAuthScope(
                  controller: cloudAuth,
                  child: SubscriptionScope(
                    controller: subscription,
                    child: CloudSyncSwitchPromptGate(
                      configStore: store,
                      child: const Scaffold(body: Text('home')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>['syncManagedVaultPush', 'syncManagedVaultPull'],
    );
    expect(find.textContaining('managed-vault push failed'), findsNothing);
    expect(engine.writeGate.value.kind, SyncWriteGateKind.graceReadOnly);
    engine.stop();
  });

  testWidgets(
      'Switching to Cloud retries push after pull recovers generation mismatch',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeCloudMediaBackupEnabled(false);

    final backend = _GenerationMismatchRecoveryPushBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
    final engine = SyncEngine(
      syncRunner: _CountingSyncRunner(),
      loadConfig: () async => SyncConfig.managedVault(
        syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
        vaultId: 'uid_1',
        baseUrl: 'https://vault.example.com',
      ),
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );
    engine.start();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: CloudAuthScope(
                  controller: cloudAuth,
                  child: SubscriptionScope(
                    controller: subscription,
                    child: CloudSyncSwitchPromptGate(
                      configStore: store,
                      child: const Scaffold(body: Text('home')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>[
        'syncManagedVaultPush',
        'syncManagedVaultPull',
        'syncManagedVaultPush',
      ],
    );
    expect(find.textContaining('managed-vault push failed'), findsNothing);
    engine.stop();
  });

  testWidgets(
      'Switching to Cloud clears stale managed-vault write gate on success',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeCloudMediaBackupEnabled(false);

    final backend = _SuccessfulPushBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
    final engine = SyncEngine(
      syncRunner: _CountingSyncRunner(),
      loadConfig: () async => null,
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );
    engine.writeGate.value =
        const SyncWriteGateState.graceReadOnly(9999999999999);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: CloudAuthScope(
                  controller: cloudAuth,
                  child: SubscriptionScope(
                    controller: subscription,
                    child: CloudSyncSwitchPromptGate(
                      configStore: store,
                      child: const Scaffold(body: Text('home')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    expect(backend.calls, contains('syncManagedVaultPush'));
    expect(engine.writeGate.value.kind, SyncWriteGateKind.open);
    engine.stop();
  });
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionController(this._status);

  SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;

  void setStatus(SubscriptionStatus next) {
    _status = next;
    notifyListeners();
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => 'test-id-token';

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

final class _Backend extends AppBackend {
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
          Uint8List key, String conversationId) async =>
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
  Future<void> editMessage(Uint8List key, String messageId, String content) =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

  @override
  Future<int> processPendingMessageEmbeddings(Uint8List key,
          {int limit = 32}) async =>
      0;

  @override
  Future<List<SimilarMessage>> searchSimilarMessages(
    Uint8List key,
    String query, {
    int topK = 10,
  }) async =>
      const <SimilarMessage>[];

  @override
  Future<int> rebuildMessageEmbeddings(Uint8List key,
          {int batchLimit = 256}) async =>
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
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 9));

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
  }) async {}

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
  }) async {}

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
}

final class _SuccessfulPushBackend extends _Backend {
  final List<String> calls = <String>[];

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPull');
    return 0;
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPush');
    return 1;
  }
}

final class _FailingPullBackend extends _Backend {
  final List<String> calls = <String>[];

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPull');
    throw StateError('managed_vault_pull_failed');
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPush');
    return 0;
  }
}

final class _GraceReadOnlyPushBackend extends _Backend {
  final List<String> calls = <String>[];

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPull');
    return 0;
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPush');
    throw Exception(
      'managed-vault push failed: HTTP 403 {"error":"grace_readonly","grace_until_ms":9999999999999}',
    );
  }
}

final class _GenerationMismatchRecoveryPushBackend extends _Backend {
  final List<String> calls = <String>[];
  var _firstPush = true;

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPull');
    return 0;
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPush');
    if (_firstPush) {
      _firstPush = false;
      throw Exception(
        'managed-vault v2 push failed: HTTP 409 {"error":"generation_mismatch","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
      );
    }
    return 1;
  }
}

final class _CountingSyncRunner implements SyncRunner {
  int pullCalls = 0;
  int pushCalls = 0;

  @override
  Future<int> pull(SyncConfig config) async {
    pullCalls += 1;
    return 0;
  }

  @override
  Future<int> push(SyncConfig config) async {
    pushCalls += 1;
    return 0;
  }
}
