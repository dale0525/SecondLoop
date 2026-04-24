part of 'sync_settings_page_test.dart';

Future<void> _ensureListItemVisible(WidgetTester tester, Finder target) async {
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
  await tester.pumpAndSettle();
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
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: Scaffold(
              body: SyncSettingsPage(
                configStore: store,
              ),
            ),
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
    Uint8List? derivedSyncKey,
    Uint8List? recoveredSyncKey,
  })  : _derivedSyncKey =
            derivedSyncKey ?? Uint8List.fromList(List<int>.filled(32, 9)),
        _recoveredSyncKey =
            recoveredSyncKey ?? Uint8List.fromList(List<int>.filled(32, 6));

  int webdavTestCalls = 0;
  int deriveSyncKeyCalls = 0;
  int recoverSyncKeyFromEnvelopeCalls = 0;
  int createSyncRecoveryEnvelopeCalls = 0;
  final int webdavPullResult;
  final int managedVaultPullResult;
  final Uint8List _derivedSyncKey;
  final Uint8List _recoveredSyncKey;

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
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    deriveSyncKeyCalls += 1;
    return Uint8List.fromList(_derivedSyncKey);
  }

  @override
  Future<Uint8List> recoverSyncKeyFromEnvelope(
    String envelopeJson,
    String passphrase,
  ) async {
    recoverSyncKeyFromEnvelopeCalls += 1;
    return Uint8List.fromList(_recoveredSyncKey);
  }

  @override
  Future<String> createSyncRecoveryEnvelope(
    Uint8List syncKey,
    String passphrase,
  ) async {
    createSyncRecoveryEnvelopeCalls += 1;
    return '{"version":1,"wrapped_sync_key_b64":"local","kdf":{"version":1}}';
  }

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

final class _ResetLocalDataSyncSettingsBackend extends _SyncSettingsBackend {
  int resetCalls = 0;

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    resetCalls += 1;
  }
}

final class _TrackingSyncSettingsBackend extends _SyncSettingsBackend {
  _TrackingSyncSettingsBackend() : super(webdavPullResult: 0);

  final List<String> calls = <String>[];

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    calls.add('webdavTest');
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    calls.add('resetLocal');
  }

  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async =>
      'snapshot-1';

  @override
  Future<void> restoreVaultRollbackSnapshot(
    Uint8List key, {
    required String snapshotPath,
  }) async {}

  @override
  Future<void> deleteVaultRollbackSnapshot({
    required String snapshotPath,
  }) async {}

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    calls.add('webdavPull:$remoteRoot');
    return 0;
  }

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    calls.add('webdavPush:$remoteRoot');
    return 0;
  }
}

final class _FailingReplaceLocalSyncSettingsBackend
    extends _SyncSettingsBackend {
  final List<String> calls = <String>[];

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    calls.add('webdavTest');
  }

  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    calls.add('createSnapshot');
    return 'snapshot-1';
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    calls.add('resetLocal');
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    calls.add('webdavPull:$remoteRoot');
    throw StateError('webdav_pull_failed');
  }

  @override
  Future<void> restoreVaultRollbackSnapshot(
    Uint8List key, {
    required String snapshotPath,
  }) async {
    calls.add('restoreSnapshot:$snapshotPath');
  }
}

final class _FailingReplaceRemoteSyncSettingsBackend
    extends _SyncSettingsBackend {
  final List<String> calls = <String>[];

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    calls.add('webdavTest');
  }

  @override
  Future<void> syncWebdavClearRemoteRoot({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    calls.add('webdavClear:$remoteRoot');
    throw StateError('webdav_clear_failed');
  }
}

final class _RollbacklessReplaceLocalSyncSettingsBackend
    extends _SyncSettingsBackend {
  final List<String> calls = <String>[];

  @override
  Future<void> syncWebdavTestConnection({
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    calls.add('webdavTest');
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    calls.add('resetLocal');
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    calls.add('webdavPull:$remoteRoot');
    return 0;
  }
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
          conversationId: 'loop_home',
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
    this.webdavPullProgressStream,
  }) : super(webdavPullResult: 0);

  final Completer<int> pushCompleter;
  final Completer<int> pullCompleter;
  final Stream<String>? webdavPullProgressStream;

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

  @override
  Stream<String> syncWebdavPullProgress(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    final stream = webdavPullProgressStream;
    if (stream != null) return stream;
    return super.syncWebdavPullProgress(
      key,
      syncKey,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remoteRoot: remoteRoot,
    );
  }
}

final class _DelayedLocalDirSyncBackend extends _SyncSettingsBackend {
  _DelayedLocalDirSyncBackend({
    required this.pushCompleter,
    required this.pullCompleter,
  }) : super(webdavPullResult: 0);

  final Completer<int> pushCompleter;
  final Completer<int> pullCompleter;

  @override
  Future<int> syncLocaldirPush(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      pushCompleter.future;

  @override
  Future<int> syncLocaldirPull(
    Uint8List key,
    Uint8List syncKey, {
    required String localDir,
    required String remoteRoot,
  }) async =>
      pullCompleter.future;
}

final class _DelayedManagedVaultSyncBackend extends _SyncSettingsBackend {
  _DelayedManagedVaultSyncBackend({
    required this.pullCompleter,
    required this.pushCompleter,
  }) : super(managedVaultPullResult: 0);

  final Completer<int> pullCompleter;
  final Completer<int> pushCompleter;
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
    return pullCompleter.future;
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
    return pushCompleter.future;
  }
}

final class _GraceReadOnlyManagedVaultSyncBackend extends _SyncSettingsBackend {
  _GraceReadOnlyManagedVaultSyncBackend() : super(managedVaultPullResult: 0);

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

final class _GenerationMismatchRecoveryManagedVaultSyncBackend
    extends _SyncSettingsBackend {
  _GenerationMismatchRecoveryManagedVaultSyncBackend()
      : super(managedVaultPullResult: 0);

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

final class _LocalUnpushedChangesRecoveryBlockedManagedVaultSyncBackend
    extends _SyncSettingsBackend {
  final List<String> calls = <String>[];

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPush');
    throw StateError(
      'managed-vault v2 recovery blocked: local_unpushed_changes',
    );
  }
}

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> push(SyncConfig config) async => 0;

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
