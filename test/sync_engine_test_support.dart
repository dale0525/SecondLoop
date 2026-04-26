part of 'sync_engine_test.dart';

SyncConfig _webdavConfig() => SyncConfig.webdav(
      syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
      remoteRoot: 'SecondLoop',
      baseUrl: 'https://example.com/dav',
      username: 'u',
      password: 'p',
    );

SyncConfig _managedVaultConfig() => SyncConfig.managedVault(
      syncKey: Uint8List.fromList(List<int>.filled(32, 2)),
      vaultId: 'vault-1',
      baseUrl: 'https://vault.example.com',
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

final class _BlockingPullRunner implements SyncRunner {
  int pushCalls = 0;
  int pullCalls = 0;
  Completer<int>? _pullCompleter;

  void completePull({required int applied}) {
    final completer = _pullCompleter;
    if (completer == null || completer.isCompleted) return;
    _pullCompleter = null;
    completer.complete(applied);
  }

  @override
  Future<int> push(SyncConfig config) async {
    pushCalls++;
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) {
    pullCalls++;
    _pullCompleter ??= Completer<int>();
    return _pullCompleter!.future;
  }
}

final class _HintPullRunner implements SyncRunner, SyncPullResultRunner {
  _HintPullRunner(this._results);

  final List<SyncPullResult> _results;

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

  @override
  Future<SyncPullResult> pullWithResult(SyncConfig config) async {
    final index = pullCalls;
    pullCalls++;
    if (_results.isEmpty) return const SyncPullResult(applied: 0);
    if (index >= _results.length) return _results.last;
    return _results[index];
  }
}

final class _OrderedRunner implements SyncRunner {
  final List<String> calls = <String>[];

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push');
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    calls.add('pull');
    return 0;
  }
}

final class _ManagedVaultRecoveryRunner implements SyncRunner {
  final List<String> calls = <String>[];

  var _firstPush = true;

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push');
    if (_firstPush) {
      _firstPush = false;
      throw Exception(
        'managed-vault v2 push failed: HTTP 409 {"error":"generation_mismatch","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
      );
    }
    return 1;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    calls.add('pull');
    return 0;
  }
}

final class _ManagedVaultInvalidBatchRunner implements SyncRunner {
  int pushCalls = 0;

  @override
  Future<int> push(SyncConfig config) async {
    pushCalls += 1;
    throw Exception(
      'managed-vault v2 push failed: HTTP 400 {"error":"invalid_batch","reason":"duplicate_client_op_id"}',
    );
  }

  @override
  Future<int> pull(SyncConfig config) async => 0;
}

final class _ManagedVaultRepeatedRecoveryRunner implements SyncRunner {
  final List<String> calls = <String>[];
  int pushCalls = 0;
  int pullCalls = 0;

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push');
    pushCalls += 1;
    if (pushCalls <= 2) {
      throw Exception(
        'managed-vault v2 push failed: HTTP 409 {"error":"generation_mismatch","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
      );
    }
    throw Exception('unexpected extra recovery push');
  }

  @override
  Future<int> pull(SyncConfig config) async {
    calls.add('pull');
    pullCalls += 1;
    return 0;
  }
}

final class _ManagedVaultRecoveryOrderingRunner
    implements SyncRunner, SyncPullResultRunner {
  final List<String> calls = <String>[];
  final Completer<void> pullStarted = Completer<void>();
  final Completer<SyncPullResult> _pullCompleter = Completer<SyncPullResult>();
  var _firstPush = true;

  void completePull({required int applied}) {
    if (_pullCompleter.isCompleted) return;
    _pullCompleter.complete(SyncPullResult(applied: applied));
  }

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push');
    if (_firstPush) {
      _firstPush = false;
      throw Exception(
        'managed-vault v2 push failed: HTTP 409 {"error":"generation_mismatch","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
      );
    }
    return 1;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    final result = await pullWithResult(config);
    return result.applied;
  }

  @override
  Future<SyncPullResult> pullWithResult(SyncConfig config) {
    calls.add('pull');
    if (!pullStarted.isCompleted) {
      pullStarted.complete();
    }
    return _pullCompleter.future;
  }
}

final class _ManagedVaultRecoveryPullFailureRunner implements SyncRunner {
  final List<String> calls = <String>[];

  var _pushCount = 0;
  var _pullCount = 0;

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push');
    _pushCount += 1;
    if (_pushCount == 1) {
      throw Exception(
        'managed-vault v2 push failed: HTTP 409 {"error":"generation_mismatch","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
      );
    }
    return 1;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    calls.add('pull');
    _pullCount += 1;
    if (_pullCount == 1) {
      throw Exception(
          'managed-vault v2 pull failed: HTTP 503 {"error":"temporary"}');
    }
    return 0;
  }
}

final class _ManagedVaultPostPushPullFailureRunner implements SyncRunner {
  final List<String> calls = <String>[];

  var _pushCount = 0;
  var _pullCount = 0;

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push');
    _pushCount += 1;
    return _pushCount;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    calls.add('pull');
    _pullCount += 1;
    if (_pullCount == 1) {
      throw Exception(
        'managed-vault v2 pull failed: HTTP 503 {"error":"temporary"}',
      );
    }
    return 0;
  }
}

final class _ManagedVaultPaymentRecoveryRunner implements SyncRunner {
  final List<String> calls = <String>[];

  var _pushCount = 0;

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push');
    _pushCount += 1;
    if (_pushCount == 1) {
      throw Exception(
        'managed-vault v2 push failed: HTTP 402 {"error":"payment_required"}',
      );
    }
    return 1;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    calls.add('pull');
    return 0;
  }
}

final class _ManagedVaultStorageQuotaRecoveryRunner implements SyncRunner {
  final List<String> calls = <String>[];

  var _pushCount = 0;

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push');
    _pushCount += 1;
    if (_pushCount == 1) {
      throw Exception(
        'managed-vault v2 push failed: HTTP 403 {"error":"storage_quota_exceeded","used_bytes":100,"limit_bytes":100}',
      );
    }
    return 1;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    calls.add('pull');
    return 0;
  }
}

final class _ManagedVaultPullRecoveryBlockedRunner implements SyncRunner {
  final List<String> calls = <String>[];

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push');
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    calls.add('pull');
    throw StateError(
      'managed-vault v2 recovery blocked: local_media_backfill_pending',
    );
  }
}

final class _ManagedVaultPostPushPullOrderingRunner
    implements SyncRunner, SyncPullResultRunner {
  final List<String> calls = <String>[];
  final Completer<void> firstPushStarted = Completer<void>();
  final Completer<void> pullStarted = Completer<void>();
  Completer<int>? _firstPushCompleter;
  Completer<SyncPullResult>? _pullCompleter;

  void completeFirstPush({required int pushed}) {
    final completer = _firstPushCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(pushed);
  }

  void completePull({required int applied}) {
    final completer = _pullCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(SyncPullResult(applied: applied));
  }

  @override
  Future<int> push(SyncConfig config) {
    calls.add('push');
    if (_firstPushCompleter == null) {
      _firstPushCompleter = Completer<int>();
      if (!firstPushStarted.isCompleted) {
        firstPushStarted.complete();
      }
      return _firstPushCompleter!.future;
    }
    return Future<int>.value(1);
  }

  @override
  Future<int> pull(SyncConfig config) async {
    final result = await pullWithResult(config);
    return result.applied;
  }

  @override
  Future<SyncPullResult> pullWithResult(SyncConfig config) {
    calls.add('pull');
    _pullCompleter ??= Completer<SyncPullResult>();
    if (!pullStarted.isCompleted) {
      pullStarted.complete();
    }
    return _pullCompleter!.future;
  }
}
