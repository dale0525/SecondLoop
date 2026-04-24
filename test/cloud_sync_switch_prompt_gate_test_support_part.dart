part of 'cloud_sync_switch_prompt_gate_test.dart';

Future<void> _tapSwitchAndChooseMerge(WidgetTester tester) async {
  await tester.tap(find.text('Switch'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Merge local and remote'));
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

final class _StorageQuotaExceededPushBackend extends _Backend {
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
    throw Exception(
      'managed-vault push failed: HTTP 403 {"error":"storage_quota_exceeded","used_bytes":10,"limit_bytes":9}',
    );
  }
}

final class _InvalidBatchPushBackend extends _Backend {
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
    throw Exception(
      'managed-vault v2 push failed: HTTP 400 {"error":"invalid_batch","reason":"duplicate_client_op_id"}',
    );
  }
}

final class _SuccessfulManagedVaultBootstrapBackend extends _Backend {
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
    return 0;
  }

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
}

final class _LocalUnpushedChangesRecoveryBlockedPushBackend extends _Backend {
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
        'managed-vault v2 recovery blocked: local_unpushed_changes');
  }
}

final class _LocalMediaBackfillRecoveryBlockedPushBackend extends _Backend {
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
      'managed-vault v2 recovery blocked: local_media_backfill_pending',
    );
  }
}

final class _TransientManagedVaultPushBackend extends _Backend {
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
    throw Exception(
      'managed-vault v2 push failed: HTTP 503 {"error":"temporary"}',
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

final class _GenerationMismatchThenGraceReadOnlyPushBackend extends _Backend {
  final List<String> calls = <String>[];
  var _pushCount = 0;

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
    _pushCount += 1;
    if (_pushCount == 1) {
      throw Exception(
        'managed-vault v2 push failed: HTTP 409 {"error":"generation_mismatch","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
      );
    }
    throw Exception(
      'managed-vault push failed: HTTP 403 {"error":"grace_readonly","grace_until_ms":9999999999999}',
    );
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
