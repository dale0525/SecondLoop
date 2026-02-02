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
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  testWidgets('removes Test connection button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final backend = _SyncSettingsBackend();

    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: null,
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.text('Test connection'), findsNothing);
  });

  testWidgets('configured passphrase shows masked placeholder', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    final backend = _SyncSettingsBackend();

    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: null,
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final passphraseField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Sync passphrase',
    );
    final field = tester.widget<TextField>(passphraseField);
    expect(field.controller?.text, isNotEmpty);
  });

  testWidgets('Save runs connection test and triggers sync on success',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final backend = _SyncSettingsBackend();

    final runner = _FakeRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => _webdavConfig(),
      pushDebounce: const Duration(milliseconds: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );

    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: engine,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Sync passphrase',
      ),
      'passphrase',
    );

    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(backend.webdavTestCalls, 1);
    expect(find.textContaining('Connection'), findsOneWidget);

    expect(runner.pullCalls, 1);
    expect(runner.pushCalls, 1);

    engine.stop();
  });

  testWidgets('Save requires sync passphrase (WebDAV)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final backend = _SyncSettingsBackend();

    await tester.pumpWidget(_wrap(
      backend: backend,
      store: store,
      engine: null,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter your sync passphrase and tap Save first.'),
      findsOneWidget,
    );
    expect(await store.readWebdavBaseUrl(), isNull);
  });

  testWidgets('Save requires sync passphrase (SecondLoop Cloud)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    final backend = _SyncSettingsBackend();
    final cloudAuth = _FakeCloudAuthController();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
              child: Scaffold(
                body: SyncSettingsPage(configStore: store),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter your sync passphrase and tap Save first.'),
      findsOneWidget,
    );
  });

  testWidgets('Manual Pull notifies sync listeners when ops were applied',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _SyncSettingsBackend(webdavPullResult: 1);

    final runner = _FakeRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () async => _webdavConfig(),
      pushDebounce: const Duration(milliseconds: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );

    var changeNotifications = 0;
    engine.changes.addListener(() => changeNotifications += 1);

    await tester.pumpWidget(wrapWithI18n(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
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
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await tester.ensureVisible(downloadButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(downloadButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(changeNotifications, 1);
    engine.stop();
  });

  testWidgets('Manual Download refreshes chat even when pull reports 0 changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _ManualPullUpdatesMessagesBackend();
    final engine = SyncEngine(
      syncRunner: _FakeRunner(),
      loadConfig: () async => _webdavConfig(),
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );

    const conversation = Conversation(
      id: 'main_stream',
      title: 'Main Stream',
      createdAtMs: 0,
      updatedAtMs: 0,
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: SyncEngineScope(
            engine: engine,
            child: wrapWithI18n(
              const MaterialApp(
                home: ChatPage(conversation: conversation),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No messages yet'), findsOneWidget);

    final chatContext = tester.element(find.byType(ChatPage));
    // ignore: discarded_futures
    Navigator.of(chatContext).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: SyncSettingsPage(configStore: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await tester.ensureVisible(downloadButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(downloadButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('hello from device A'), findsOneWidget);
    engine.stop();
  });

  testWidgets('Cloud Download shows up-to-date message when no new changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _SyncSettingsBackend(managedVaultPullResult: 0);
    final cloudAuth = _FakeCloudAuthController();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: cloudAuth,
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await tester.ensureVisible(downloadButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(downloadButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('No new changes'), findsOneWidget);
  });

  testWidgets('Manual Upload/Download shows progress indicator',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final pushCompleter = Completer<int>();
    final pullCompleter = Completer<int>();
    final backend = _DelayedSyncBackend(
      pushCompleter: pushCompleter,
      pullCompleter: pullCompleter,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
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
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Server address',
      ),
      'https://example.com/dav',
    );
    await tester.pump();

    final scrollable = find.byType(ListView);
    final uploadButton = find.widgetWithText(OutlinedButton, 'Upload');
    await tester.dragUntilVisible(
      uploadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(uploadButton);
    await tester.pump();

    expect(tester.widget<OutlinedButton>(uploadButton).onPressed, isNull);
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_manual_progress_percent')),
        findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('0%'), findsNothing);

    pushCompleter.complete(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsNothing);
    expect(find.byKey(const ValueKey('sync_manual_progress_percent')),
        findsNothing);

    final downloadButton = find.widgetWithText(OutlinedButton, 'Download');
    await tester.dragUntilVisible(
      downloadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(downloadButton);
    await tester.pump();

    expect(find.byKey(const ValueKey('sync_manual_progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_manual_progress_percent')),
        findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('0%'), findsNothing);

    pullCompleter.complete(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsNothing);
    expect(find.byKey(const ValueKey('sync_manual_progress_percent')),
        findsNothing);
  });
}

Widget _wrap({
  required AppBackend backend,
  required SyncConfigStore store,
  required SyncEngine? engine,
}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SyncEngineScope(
          engine: engine,
          child: Scaffold(
            body: SyncSettingsPage(configStore: store),
          ),
        ),
      ),
    ),
  );
}

SyncConfig _webdavConfig() => SyncConfig.webdav(
      syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
      remoteRoot: 'SecondLoop',
      baseUrl: 'https://example.com/dav',
      username: 'u',
      password: 'p',
    );

final class _FakeRunner implements SyncRunner {
  int pushCalls = 0;
  int pullCalls = 0;

  @override
  Future<int> push(SyncConfig config) async {
    pushCalls++;
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    pullCalls++;
    return 0;
  }
}

class _SyncSettingsBackend extends AppBackend {
  _SyncSettingsBackend({
    this.webdavPullResult = 0,
    this.managedVaultPullResult = 0,
  });

  int webdavTestCalls = 0;
  final int webdavPullResult;
  final int managedVaultPullResult;

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
  Future<List<Conversation>> listConversations(Uint8List key) async => const [];

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
  Future<void> editMessage(
          Uint8List key, String messageId, String content) async =>
      throw UnimplementedError();

  @override
  Future<void> setMessageDeleted(
          Uint8List key, String messageId, bool isDeleted) async =>
      throw UnimplementedError();

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {}

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
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    webdavTestCalls += 1;
  }

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
      webdavPullResult;

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
      managedVaultPullResult;
}

final class _ManualPullUpdatesMessagesBackend extends _SyncSettingsBackend {
  _ManualPullUpdatesMessagesBackend() : super(webdavPullResult: 0);

  bool _pulledOnce = false;
  final List<Message> _messages = <Message>[];

  @override
  Future<List<Message>> listMessages(
          Uint8List key, String conversationId) async =>
      List<Message>.from(_messages);

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    if (!_pulledOnce) {
      _pulledOnce = true;
      _messages.add(
        const Message(
          id: 'm1',
          conversationId: 'main_stream',
          role: 'user',
          content: 'hello from device A',
          createdAtMs: 0,
          isMemory: true,
        ),
      );
    }
    return 0;
  }
}

final class _DelayedSyncBackend extends _SyncSettingsBackend {
  _DelayedSyncBackend({
    required this.pushCompleter,
    required this.pullCompleter,
  }) : super(webdavPullResult: 0);

  final Completer<int> pushCompleter;
  final Completer<int> pullCompleter;

  @override
  Future<int> syncWebdavPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      pushCompleter.future;

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      pullCompleter.future;
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
