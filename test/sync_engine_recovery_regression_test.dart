import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test(
      'ordinary managed-vault push clears stale retry-after-recovery intent before mandatory pull',
      () {
    fakeAsync((async) {
      final runner = _ManagedVaultStaleRecoveryIntentRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _managedVaultConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
      );

      engine.start();
      engine.triggerPushNow();
      async.flushMicrotasks();
      expect(runner.calls, <String>['push', 'pull']);

      engine.triggerPushNow();
      async.flushMicrotasks();

      expect(runner.calls, <String>['push', 'pull', 'push', 'pull']);

      engine.stop();
    });
  });
}

SyncConfig _managedVaultConfig() => SyncConfig.managedVault(
      syncKey: Uint8List.fromList(List<int>.filled(32, 7)),
      vaultId: 'vault-1',
      baseUrl: 'https://vault.example.com',
    );

final class _ManagedVaultStaleRecoveryIntentRunner implements SyncRunner {
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
        'managed-vault v2 pull failed: HTTP 503 {"error":"temporary"}',
      );
    }
    return 0;
  }
}
