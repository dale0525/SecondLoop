part of 'sync_settings_page_delete_actions_test.dart';

Widget _wrap({
  required AppBackend backend,
  required SyncConfigStore store,
  SyncEngine? engine,
  CloudAuthController? cloudAuthController,
  AppPlatformCapabilities? capabilities,
}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppPlatformCapabilityScope(
        capabilities: capabilities ?? AppPlatformCapabilities.native(),
        child: AppBackendScope(
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

Future<void> _confirmDeletionTwice(WidgetTester tester) async {
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete'));
}

final class _DeleteActionsBackend extends AppBackend {
  _DeleteActionsBackend({
    this.webdavClearRemoteRootError,
    this.webdavClearRemoteRootCompleter,
    this.resetLocalDataCompleter,
    this.savedSessionKey,
  });

  int clearLocalCacheCalls = 0;
  int resetLocalDataCalls = 0;
  int syncWebdavClearRemoteRootCalls = 0;
  int syncLocaldirClearRemoteRootCalls = 0;
  int syncManagedVaultClearVaultCalls = 0;
  String? lastManagedVaultClearVaultId;
  String? lastManagedVaultClearBaseUrl;
  String? lastWebdavClearBaseUrl;
  String? lastWebdavClearRemoteRoot;
  final Object? webdavClearRemoteRootError;
  final Completer<void>? webdavClearRemoteRootCompleter;
  final Completer<void>? resetLocalDataCompleter;
  final Uint8List? savedSessionKey;

  @override
  Future<void> init() async {}

  @override
  Future<bool> isMasterPasswordSet() async => true;

  @override
  Future<bool> readAutoUnlockEnabled() async => true;

  @override
  Future<void> persistAutoUnlockEnabled({required bool enabled}) async {}

  @override
  Future<Uint8List?> loadSavedSessionKey() async => savedSessionKey;

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
    final completer = resetLocalDataCompleter;
    if (completer != null) {
      await completer.future;
    }
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
    lastManagedVaultClearBaseUrl = baseUrl;
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

final class _BlockingPushRunner implements SyncRunner {
  int pushCalls = 0;
  final Completer<void> pushStarted = Completer<void>();
  final Completer<void> _pushCompleter = Completer<void>();

  void completePush() {
    if (_pushCompleter.isCompleted) return;
    _pushCompleter.complete();
  }

  @override
  Future<int> push(SyncConfig config) async {
    pushCalls += 1;
    if (!pushStarted.isCompleted) {
      pushStarted.complete();
    }
    await _pushCompleter.future;
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) async => 0;
}

final class _FakeCloudAuthController implements CloudAuthController {
  _FakeCloudAuthController({this.userId = 'uid_1'});

  final String userId;

  @override
  Future<String?> getIdToken() async => 'test-id-token';

  @override
  String? get uid => userId;

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
