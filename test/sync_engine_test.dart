import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_result.dart';

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
        retryPushAfterRecoveryPull: true,
        backendType: SyncBackendType.managedVault,
      ),
      isFalse,
    );
    expect(
      SyncEngine.shouldPrioritizePushOverPullForTest(
        pushQueued: true,
        pullQueued: true,
        retryPushAfterRecoveryPull: false,
        backendType: SyncBackendType.managedVault,
      ),
      isTrue,
    );
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
