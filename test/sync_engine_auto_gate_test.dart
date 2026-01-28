import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/sync/sync_engine.dart';

void main() {
  test('autoRunGate blocks debounced pushes while false', () {
    fakeAsync((async) {
      final runner = _FakeRunner();
      var allow = false;
      final engine = SyncEngine(
        syncRunner: runner,
        loadConfig: () async => _webdavConfig(),
        pushDebounce: const Duration(milliseconds: 100),
        pullInterval: const Duration(days: 1),
        pullJitter: Duration.zero,
        pullOnStart: false,
        autoRunGate: () async => allow,
      );

      engine.start();
      engine.notifyLocalMutation();
      async.flushMicrotasks();

      async.elapse(const Duration(milliseconds: 200));
      async.flushMicrotasks();
      expect(runner.pushCalls, 0);

      allow = true;
      engine.triggerPullNow();
      async.flushMicrotasks();

      expect(runner.pushCalls, 1);
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
