part of 'sync_engine_gate_media_uploads_test.dart';

final class _FakeConnectivityPlatform extends ConnectivityPlatform {
  _FakeConnectivityPlatform._(this._results);

  factory _FakeConnectivityPlatform.wifi() {
    return _FakeConnectivityPlatform._(
      const <ConnectivityResult>[ConnectivityResult.wifi],
    );
  }

  final List<ConnectivityResult> _results;

  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _results;
}

final class _BlockingLifecycleBackend extends TestAppBackend {
  int webdavPushOpsOnlyCalls = 0;
  int webdavPullCalls = 0;

  bool _blockNextPull = false;
  bool hasBlockedPull = false;
  Completer<int>? _pullCompleter;

  void blockNextPull() {
    _blockNextPull = true;
    hasBlockedPull = false;
  }

  void completeBlockedPull({required int applied}) {
    final completer = _pullCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(applied);
  }

  @override
  Future<int> syncWebdavPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    webdavPushOpsOnlyCalls++;
    return 0;
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    webdavPullCalls++;
    if (!_blockNextPull) {
      return Future<int>.value(0);
    }

    _blockNextPull = false;
    hasBlockedPull = true;
    _pullCompleter = Completer<int>();
    return _pullCompleter!.future;
  }
}

final class _RecordingBackend extends TestAppBackend {
  _RecordingBackend({List<CloudMediaBackup>? dueBackups})
      : _dueBackups = List<CloudMediaBackup>.from(dueBackups ?? const []);

  int webdavPushCalls = 0;
  int webdavPushOpsOnlyCalls = 0;
  int webdavUploadAttachmentCalls = 0;
  int markUploadedCalls = 0;
  int cloudMediaBackfillCalls = 0;

  final List<CloudMediaBackup> _dueBackups;
  final Set<String> _uploaded = <String>{};

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    webdavPushCalls++;
    return 0;
  }

  @override
  Future<int> syncWebdavPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    webdavPushOpsOnlyCalls++;
    return 0;
  }

  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
    String? scopeId,
  }) async {
    return _dueBackups
        .where((b) => !_uploaded.contains(b.attachmentSha256))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
    String? scopeId,
  }) async {
    markUploadedCalls++;
    _uploaded.add(attachmentSha256);
  }

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
    String? scopeId,
  }) async {
    // ignored
  }

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
    String? scopeId,
  }) async {
    cloudMediaBackfillCalls++;
    return 0;
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) async {
    final pendingCount = _dueBackups
        .where((b) => !_uploaded.contains(b.attachmentSha256))
        .length;
    return CloudMediaBackupSummary(
      pending: pendingCount,
      failed: 0,
      uploaded: _uploaded.length,
    );
  }

  @override
  Future<bool> syncWebdavUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) async {
    webdavUploadAttachmentCalls++;
    return true;
  }

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
}

final class _ManagedVaultRecordingBackend extends _RecordingBackend {
  _ManagedVaultRecordingBackend({super.dueBackups});

  int managedVaultPushCalls = 0;
  int managedVaultPushOpsOnlyCalls = 0;
  int managedVaultPullCalls = 0;
  int managedVaultUploadAttachmentCalls = 0;

  Completer<int>? _pullCompleter;

  void completePull({required int applied}) {
    final completer = _pullCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(applied);
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
    return 0;
  }

  @override
  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushOpsOnlyCalls++;
    return 0;
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) {
    managedVaultPullCalls++;
    _pullCompleter = Completer<int>();
    return _pullCompleter!.future;
  }

  @override
  Future<bool> syncManagedVaultUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    managedVaultUploadAttachmentCalls++;
    return true;
  }
}

final class _ManagedVaultPullOnlyRecoveryBackend
    extends _ManagedVaultRecordingBackend {
  _ManagedVaultPullOnlyRecoveryBackend({super.dueBackups});

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
    throw Exception(
      'managed-vault push failed: HTTP 403 {"error":"grace_readonly","grace_until_ms":9999999999999}',
    );
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPullCalls++;
    return 0;
  }
}

final class _ManagedVaultRetryingUploadBackend
    extends _ManagedVaultRecordingBackend {
  _ManagedVaultRetryingUploadBackend({super.dueBackups});

  final Set<String> _failedUploads = <String>{};

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPullCalls++;
    return 0;
  }

  @override
  Future<bool> syncManagedVaultUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    managedVaultUploadAttachmentCalls++;
    if (!_failedUploads.contains(sha256)) {
      _failedUploads.add(sha256);
      throw Exception('transient managed-vault media upload failure');
    }
    return true;
  }

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
    String? scopeId,
  }) async {}

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) async {
    final pendingCount = _dueBackups
        .where((b) => !_uploaded.contains(b.attachmentSha256))
        .length;
    final failedCount =
        _failedUploads.where((sha256) => !_uploaded.contains(sha256)).length;
    return CloudMediaBackupSummary(
      pending: pendingCount,
      failed: failedCount,
      uploaded: _uploaded.length,
    );
  }
}

final class _ManagedVaultInvalidBatchBackend
    extends _ManagedVaultRecordingBackend {
  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
    throw Exception(
      'managed-vault v2 push failed: HTTP 400 {"error":"invalid_batch","reason":"duplicate_client_op_id"}',
    );
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPullCalls++;
    return 0;
  }
}

final class _ManagedVaultPullRecoveryBlockedBackend
    extends _ManagedVaultRecordingBackend {
  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
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
    managedVaultPullCalls++;
    throw StateError(
      'managed-vault v2 recovery blocked: local_media_backfill_pending',
    );
  }
}

final class _ManagedVaultTransientPullFailureBackend
    extends _ManagedVaultRecordingBackend {
  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
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
    managedVaultPullCalls++;
    throw StateError(
      'managed-vault v2 pull failed: HTTP 503 {"error":"temporary"}',
    );
  }
}

final class _ManagedVaultTokenRecordingBackend extends TestAppBackend {
  final List<String> managedVaultPushTokens = <String>[];

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushTokens.add(idToken);
    return 0;
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async =>
      0;
}

final class _MutableCloudAuthController implements CloudAuthController {
  _MutableCloudAuthController({
    required this.uidValue,
    required this.tokenValue,
  });

  final String uidValue;
  final String tokenValue;

  @override
  Future<String?> getIdToken() async => tokenValue;

  @override
  String? get uid => uidValue;

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

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;

  set status(SubscriptionStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  Future<String?> getIdToken() async => 'test-id-token';

  @override
  String? get uid => 'uid-1';

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
