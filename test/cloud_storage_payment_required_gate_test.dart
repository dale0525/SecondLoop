import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('payment_required from pull sets gate and clears after success', () {
    fakeAsync((async) {
      final runner = _PaymentRequiredPullRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _managedVaultConfig(),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
      );

      engine.start();

      engine.triggerPullNow();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(runner.pullCalls, 1);
      expect(engine.writeGate.value.kind, SyncWriteGateKind.paymentRequired);

      runner.shouldSucceed = true;
      engine.triggerPullNow();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(runner.pullCalls, 2);
      expect(engine.writeGate.value.kind, SyncWriteGateKind.open);

      engine.stop();
    });
  });
}

SyncConfig _managedVaultConfig() => SyncConfig.managedVault(
      syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
      vaultId: 'test_vault',
      baseUrl: 'https://vault.test',
    );

final class _PaymentRequiredPullRunner implements SyncRunner {
  int pullCalls = 0;
  bool shouldSucceed = false;

  @override
  Future<int> push(SyncConfig config) async => 0;

  @override
  Future<int> pull(SyncConfig config) async {
    pullCalls += 1;
    if (shouldSucceed) return 0;
    throw Exception(
      'managed-vault pull failed: HTTP 402 {"error":"payment_required"}',
    );
  }
}
