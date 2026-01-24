import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('grace_readonly blocks further pushes but still allows pulls', () {
    fakeAsync((async) {
      final runner = _GraceReadOnlyRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _managedVaultConfig(),
        pushDebounce: const Duration(milliseconds: 10),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
      );

      engine.start();

      engine.notifyLocalMutation();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 10));
      async.flushMicrotasks();

      expect(runner.pushCalls, 1);
      expect(engine.writeGate.value.kind, SyncWriteGateKind.graceReadOnly);
      expect(engine.writeGate.value.graceUntilMs, isNotNull);

      engine.notifyLocalMutation();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 10));
      async.flushMicrotasks();

      expect(runner.pushCalls, 1);

      engine.triggerPullNow();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(runner.pullCalls, 1);

      engine.stop();
    });
  });
}

SyncConfig _managedVaultConfig() => SyncConfig.managedVault(
      syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
      vaultId: 'test_vault',
      baseUrl: 'https://vault.test',
    );

final class _GraceReadOnlyRunner implements SyncRunner {
  int pushCalls = 0;
  int pullCalls = 0;

  @override
  Future<int> push(SyncConfig config) async {
    pushCalls += 1;
    throw Exception(
      'managed-vault push failed: HTTP 403 {"error":"grace_readonly","grace_until_ms":9999999999999}',
    );
  }

  @override
  Future<int> pull(SyncConfig config) async {
    pullCalls += 1;
    return 0;
  }
}
