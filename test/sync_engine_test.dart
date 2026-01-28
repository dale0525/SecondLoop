import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine.dart';

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

  test('notifies changes periodically during long pull', () {
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

      expect(
        changeNotifications,
        greaterThan(0),
        reason: 'expected periodic change notifications during long pull',
      );

      runner.completePull(applied: 0);
      async.flushMicrotasks();
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
  int pullCalls = 0;
  Completer<int>? _pullCompleter;

  void completePull({required int applied}) {
    _pullCompleter?.complete(applied);
  }

  @override
  Future<int> push(SyncConfig config) async => 0;

  @override
  Future<int> pull(SyncConfig config) {
    pullCalls++;
    _pullCompleter ??= Completer<int>();
    return _pullCompleter!.future;
  }
}
