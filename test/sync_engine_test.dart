import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_result.dart';

part 'sync_engine_test_support.dart';

void main() {
  test('debounces push after local mutations', () {
    fakeAsync((async) {
      final runner = _FakeRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(milliseconds: 100),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
      );

      engine.start();

      engine.notifyLocalMutation();
      engine.notifyLocalMutation();
      async.flushMicrotasks();

      async.elapse(const Duration(milliseconds: 99));
      async.flushMicrotasks();
      expect(runner.pushCalls, 0);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(runner.pushCalls, 1);

      engine.stop();
    });
  });

  test('pulls periodically while running', () {
    fakeAsync((async) {
      final runner = _FakeRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(milliseconds: 10),
        pullInterval: const Duration(seconds: 10),
        pullJitter: Duration.zero,
        pullOnStart: false,
      );

      engine.start();
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(runner.pullCalls, 1);

      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(runner.pullCalls, 2);

      engine.stop();
    });
  });

  test('does not notify changes during long pull progress', () {
    fakeAsync((async) {
      final runner = _BlockingPullRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: true,
      );

      var changeNotifications = 0;
      engine.changes.addListener(() => changeNotifications++);

      engine.start();
      async.flushMicrotasks();

      expect(runner.pullCalls, 1);
      expect(changeNotifications, 0);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(changeNotifications, 0);

      runner.completePull(applied: 0);
      async.flushMicrotasks();
      expect(changeNotifications, 0);

      engine.stop();
    });
  });

  test('notifies once after long pull applies changes', () {
    fakeAsync((async) {
      final runner = _BlockingPullRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: true,
      );

      var changeNotifications = 0;
      engine.changes.addListener(() => changeNotifications++);

      engine.start();
      async.flushMicrotasks();

      expect(runner.pullCalls, 1);
      expect(changeNotifications, 0);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(changeNotifications, 0);

      runner.completePull(applied: 2);
      async.flushMicrotasks();
      expect(changeNotifications, 1);

      engine.stop();
    });
  });

  test('notifies when pull result requests refresh with zero applied', () {
    fakeAsync((async) {
      final runner = _HintPullRunner(
        const <SyncPullResult>[
          SyncPullResult(applied: 0, shouldRefreshUi: true),
        ],
      );
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: true,
        zeroApplyRefreshMinInterval: Duration.zero,
      );

      var changeNotifications = 0;
      engine.changes.addListener(() => changeNotifications++);

      engine.start();
      async.flushMicrotasks();

      expect(runner.pullCalls, 1);
      expect(changeNotifications, 1);

      engine.stop();
    });
  });

  test('throttles zero-applied refresh hints', () {
    fakeAsync((async) {
      final runner = _HintPullRunner(
        const <SyncPullResult>[
          SyncPullResult(applied: 0, shouldRefreshUi: true),
          SyncPullResult(applied: 0, shouldRefreshUi: true),
          SyncPullResult(applied: 0, shouldRefreshUi: true),
        ],
      );
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
        zeroApplyRefreshMinInterval: const Duration(seconds: 60),
        nowMsProvider: () => async.elapsed.inMilliseconds,
      );

      var changeNotifications = 0;
      engine.changes.addListener(() => changeNotifications++);
      engine.start();

      engine.triggerPullNow();
      async.flushMicrotasks();
      expect(changeNotifications, 1);

      async.elapse(const Duration(seconds: 10));
      engine.triggerPullNow();
      async.flushMicrotasks();
      expect(changeNotifications, 1);

      async.elapse(const Duration(seconds: 60));
      engine.triggerPullNow();
      async.flushMicrotasks();
      expect(changeNotifications, 2);

      engine.stop();
    });
  });

  test('stop flushes queued push after blocking pull completes', () {
    fakeAsync((async) {
      final runner = _BlockingPullRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: true,
      );

      engine.start();
      async.flushMicrotasks();
      expect(runner.pullCalls, 1);

      engine.notifyLocalMutation();
      async.flushMicrotasks();
      expect(runner.pushCalls, 0);

      engine.stop();
      runner.completePull(applied: 0);
      async.flushMicrotasks();

      expect(runner.pushCalls, 1);
    });
  });

  test('stopImmediatelyAndWait waits for busy stopped engine', () {
    fakeAsync((async) {
      final runner = _BlockingPullRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: true,
      );

      engine.start();
      async.flushMicrotasks();
      expect(runner.pullCalls, 1);

      engine.stop();
      expect(engine.isRunning, isFalse);

      var stopped = false;
      unawaited(engine.stopImmediatelyAndWait().then((_) {
        stopped = true;
      }));
      async.flushMicrotasks();

      expect(stopped, isFalse);

      runner.completePull(applied: 0);
      async.flushMicrotasks();

      expect(stopped, isTrue);
    });
  });

  test('stop-after-drain ignores new pull requests', () {
    fakeAsync((async) {
      final runner = _BlockingPullRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: true,
      );

      engine.start();
      async.flushMicrotasks();
      expect(runner.pullCalls, 1);

      engine.notifyLocalMutation();
      engine.stop();
      engine.triggerPullNow();

      runner.completePull(applied: 0);
      async.flushMicrotasks();

      expect(runner.pullCalls, 1);
      expect(runner.pushCalls, 1);
    });
  });

  test('start cancels stop-after-drain and keeps engine running', () {
    fakeAsync((async) {
      final runner = _BlockingPullRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: true,
      );

      engine.start();
      async.flushMicrotasks();
      expect(runner.pullCalls, 1);

      engine.notifyLocalMutation();
      engine.stop();
      expect(engine.isRunning, isFalse);

      engine.start();
      expect(engine.isRunning, isTrue);

      runner.completePull(applied: 0);
      async.flushMicrotasks();
      expect(runner.pullCalls, 2);

      engine.triggerPushNow();
      async.flushMicrotasks();

      expect(runner.pushCalls, 0);

      runner.completePull(applied: 0);
      async.flushMicrotasks();

      expect(runner.pushCalls, 1);

      engine.triggerPushNow();
      async.flushMicrotasks();

      expect(runner.pushCalls, 2);
      expect(engine.isRunning, isTrue);

      engine.stop();
    });
  });

  test('stop-after-drain preserves queued push when autoRunGate blocks', () {
    fakeAsync((async) {
      final runner = _BlockingPullRunner();
      var allow = true;
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: true,
        autoRunGate: () async => allow,
      );

      engine.start();
      async.flushMicrotasks();
      expect(runner.pullCalls, 1);

      engine.notifyLocalMutation();
      engine.stop();

      allow = false;
      runner.completePull(applied: 0);
      async.flushMicrotasks();

      expect(runner.pushCalls, 0);
      expect(engine.isRunning, isFalse);

      allow = true;
      engine.start();
      async.flushMicrotasks();
      expect(runner.pullCalls, 2);

      runner.completePull(applied: 0);
      async.flushMicrotasks();

      expect(runner.pushCalls, 1);

      engine.stop();
    });
  });

  test('managed vault prioritizes queued push before queued pull', () {
    fakeAsync((async) {
      final runner = _OrderedRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _managedVaultConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
      );

      engine.start();
      engine.triggerPullNow();
      engine.triggerPushNow();
      async.flushMicrotasks();

      expect(runner.calls, <String>['push', 'pull']);

      engine.stop();
    });
  });

  test('managed vault local mutation converges with pull after push', () {
    fakeAsync((async) {
      final runner = _OrderedRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _managedVaultConfig(),
        pushDebounce: const Duration(milliseconds: 100),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
      );

      engine.start();
      engine.notifyLocalMutation();

      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();

      expect(runner.calls, <String>['push', 'pull']);

      engine.stop();
    });
  });

  test('managed vault retries push after pull recovers generation mismatch',
      () {
    fakeAsync((async) {
      final runner = _ManagedVaultRecoveryRunner();
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

      expect(runner.calls, <String>['push', 'pull', 'push', 'pull']);

      engine.stop();
    });
  });

  test(
      'managed vault caps retry-after-recovery loops on repeated generation mismatch',
      () {
    fakeAsync((async) {
      final runner = _ManagedVaultRepeatedRecoveryRunner();
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

      expect(runner.pushCalls, 2);
      expect(runner.pullCalls, 1);
      expect(runner.calls, <String>['push', 'pull', 'push']);

      engine.stop();
    });
  });

  test('managed vault invalid_batch stops subsequent automatic pushes', () {
    fakeAsync((async) {
      final runner = _ManagedVaultInvalidBatchRunner();
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

      engine.notifyLocalMutation();
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 10));
      async.flushMicrotasks();

      expect(runner.pushCalls, 1);

      engine.triggerPushNow();
      async.flushMicrotasks();

      expect(runner.pushCalls, 1);

      engine.stop();
    });
  });

  test('managed vault recovery pull is not preempted by newly queued push work',
      () async {
    final recoveryDecisionStarted = Completer<void>();
    final releaseRecoveryDecision = Completer<SyncConfig?>();
    final runner = _ManagedVaultRecoveryOrderingRunner();
    var loadConfigCalls = 0;
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: () {
        loadConfigCalls += 1;
        if (loadConfigCalls == 2) {
          recoveryDecisionStarted.complete();
          return releaseRecoveryDecision.future;
        }
        return Future<SyncConfig?>.value(_managedVaultConfig());
      },
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );

    engine.start();
    engine.triggerPushNow();

    await recoveryDecisionStarted.future;
    engine.notifyLocalMutation();
    releaseRecoveryDecision.complete(_managedVaultConfig());

    await runner.pullStarted.future;
    expect(runner.calls.length, greaterThanOrEqualTo(2));
    expect(runner.calls[0], 'push');
    expect(runner.calls[1], 'pull');

    runner.completePull(applied: 0);
    await Future<void>.delayed(Duration.zero);
    engine.stop();
  });

  test('managed vault recovery policy does not prioritize push over pull', () {
    expect(
      SyncEngine.shouldPrioritizePushOverPullForTest(
        pushQueued: true,
        pullQueued: true,
        pendingPullAfterPush: false,
        retryPushAfterRecoveryPull: true,
        backendType: SyncBackendType.managedVault,
      ),
      isFalse,
    );
    expect(
      SyncEngine.shouldPrioritizePushOverPullForTest(
        pushQueued: true,
        pullQueued: true,
        pendingPullAfterPush: false,
        retryPushAfterRecoveryPull: false,
        backendType: SyncBackendType.managedVault,
      ),
      isTrue,
    );
  });

  test('managed vault successful pull reopens payment gate for later pushes',
      () {
    fakeAsync((async) {
      final runner = _ManagedVaultPaymentRecoveryRunner();
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

      expect(runner.calls, <String>['push']);
      expect(engine.writeGate.value.kind, SyncWriteGateKind.paymentRequired);

      engine.triggerPullNow();
      async.flushMicrotasks();

      expect(runner.calls, <String>['push', 'pull']);
      expect(engine.writeGate.value.kind, SyncWriteGateKind.open);

      engine.triggerPushNow();
      async.flushMicrotasks();

      expect(runner.calls, <String>['push', 'pull', 'push', 'pull']);

      engine.stop();
    });
  });

  test(
      'managed vault successful pull reopens storage quota gate for later pushes',
      () {
    fakeAsync((async) {
      final runner = _ManagedVaultStorageQuotaRecoveryRunner();
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

      expect(runner.calls, <String>['push']);
      expect(
        engine.writeGate.value.kind,
        SyncWriteGateKind.storageQuotaExceeded,
      );

      engine.triggerPullNow();
      async.flushMicrotasks();

      expect(runner.calls, <String>['push', 'pull']);
      expect(engine.writeGate.value.kind, SyncWriteGateKind.open);

      engine.triggerPushNow();
      async.flushMicrotasks();

      expect(runner.calls, <String>['push', 'pull', 'push', 'pull']);

      engine.stop();
    });
  });

  test('managed vault pull blocker flips gate to local repair required', () {
    fakeAsync((async) {
      final runner = _ManagedVaultPullRecoveryBlockedRunner();
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _managedVaultConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
      );

      engine.start();
      engine.triggerPullNow();
      async.flushMicrotasks();

      expect(runner.calls, <String>['pull']);
      expect(
        engine.writeGate.value.kind,
        SyncWriteGateKind.localRepairRequired,
      );

      engine.stop();
    });
  });

  test(
      'managed vault keeps retry-after-recovery intent across transient pull failures',
      () {
    fakeAsync((async) {
      final runner = _ManagedVaultRecoveryPullFailureRunner();
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

      engine.triggerPullNow();
      async.flushMicrotasks();
      expect(runner.calls, <String>['push', 'pull', 'pull', 'push', 'pull']);

      engine.stop();
    });
  });

  test(
      'managed vault keeps mandatory post-push pull queued across transient pull failures',
      () {
    fakeAsync((async) {
      final runner = _ManagedVaultPostPushPullFailureRunner();
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
      expect(runner.calls, <String>['push', 'pull', 'pull', 'push', 'pull']);

      engine.stop();
    });
  });

  test(
      'managed vault mandatory pull after push is not preempted by new push work',
      () async {
    final runner = _ManagedVaultPostPushPullOrderingRunner();
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

    await runner.firstPushStarted.future;
    engine.triggerPushNow();
    runner.completeFirstPush(pushed: 1);

    await runner.pullStarted.future;
    expect(runner.calls.length, greaterThanOrEqualTo(2));
    expect(runner.calls[0], 'push');
    expect(runner.calls[1], 'pull');

    runner.completePull(applied: 0);
    await Future<void>.delayed(Duration.zero);
    engine.stop();
  });

  test('does not notify zero-applied refresh when refresh_v2 is disabled', () {
    fakeAsync((async) {
      final runner = _HintPullRunner(
        const <SyncPullResult>[
          SyncPullResult(applied: 0, shouldRefreshUi: true),
        ],
      );
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(days: 1),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: true,
        zeroApplyRefreshMinInterval: Duration.zero,
        syncRefreshV2EnabledProvider: () async => false,
      );

      var changeNotifications = 0;
      engine.changes.addListener(() => changeNotifications++);

      engine.start();
      async.flushMicrotasks();

      expect(runner.pullCalls, 1);
      expect(changeNotifications, 0);

      engine.stop();
    });
  });
}
