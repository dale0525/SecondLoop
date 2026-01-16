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
