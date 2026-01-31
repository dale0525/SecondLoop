import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/cloud_sync_switch_prompt_gate.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
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

  testWidgets('Switching to Cloud requires sync passphrase if missing',
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

    expect(find.text('Set sync passphrase'), findsOneWidget);

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Sync passphrase',
      ),
      'passphrase',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save passphrase'));
    await tester.pumpAndSettle();

    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(await store.readRemoteRoot(), 'uid_1');
    final syncKey = await store.readSyncKey();
    expect(syncKey, isNotNull);
    expect(syncKey!.length, 32);
  });

  testWidgets('Cloud sync switch prompt continues to cloud embeddings prompt',
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

    expect(find.byType(AlertDialog), findsOneWidget);
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
  Future<Conversation> getOrCreateMainStreamConversation(Uint8List key) async =>
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
