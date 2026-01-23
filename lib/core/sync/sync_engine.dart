import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show Listenable, ValueNotifier;

enum SyncBackendType {
  webdav,
  localDir,
}

final class SyncConfig {
  SyncConfig._({
    required this.backendType,
    required this.syncKey,
    required this.remoteRoot,
    this.baseUrl,
    this.username,
    this.password,
    this.localDir,
  });

  factory SyncConfig.webdav({
    required Uint8List syncKey,
    required String remoteRoot,
    required String baseUrl,
    String? username,
    String? password,
  }) {
    return SyncConfig._(
      backendType: SyncBackendType.webdav,
      syncKey: syncKey,
      remoteRoot: remoteRoot,
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
  }

  factory SyncConfig.localDir({
    required Uint8List syncKey,
    required String remoteRoot,
    required String localDir,
  }) {
    return SyncConfig._(
      backendType: SyncBackendType.localDir,
      syncKey: syncKey,
      remoteRoot: remoteRoot,
      localDir: localDir,
    );
  }

  final SyncBackendType backendType;
  final Uint8List syncKey;
  final String remoteRoot;

  final String? baseUrl;
  final String? username;
  final String? password;

  final String? localDir;
}

abstract class SyncRunner {
  Future<int> push(SyncConfig config);
  Future<int> pull(SyncConfig config);
}

typedef SyncConfigLoader = Future<SyncConfig?> Function();

final class SyncEngine {
  SyncEngine({
    required this.syncRunner,
    required this.loadConfig,
    this.pushDebounce = const Duration(seconds: 2),
    this.pullInterval = const Duration(seconds: 20),
    this.pullJitter = const Duration(seconds: 5),
    this.pullOnStart = true,
    Random? random,
  }) : _random = random ?? Random();

  final SyncRunner syncRunner;
  final SyncConfigLoader loadConfig;

  final Duration pushDebounce;
  final Duration pullInterval;
  final Duration pullJitter;
  final bool pullOnStart;
  final Random _random;

  final ValueNotifier<int> _changeCounter = ValueNotifier<int>(0);
  Listenable get changes => _changeCounter;

  bool get isRunning => _running;

  bool _running = false;
  bool _busy = false;
  bool _pushQueued = false;
  bool _pullQueued = false;

  Timer? _pushDebounceTimer;
  Timer? _pullTimer;

  void start() {
    if (_running) return;
    _running = true;

    if (pullOnStart) {
      _queuePull();
    }
    _scheduleNextPull();
  }

  void stop() {
    if (!_running) return;
    _running = false;

    _pushDebounceTimer?.cancel();
    _pushDebounceTimer = null;

    _pullTimer?.cancel();
    _pullTimer = null;

    _pushQueued = false;
    _pullQueued = false;
  }

  void _notifyChange() {
    _changeCounter.value++;
  }

  void notifyLocalMutation() {
    _notifyChange();
    if (!_running) return;
    _pushDebounceTimer?.cancel();
    _pushDebounceTimer = Timer(pushDebounce, _queuePush);
  }

  void notifyExternalChange() {
    _notifyChange();
  }

  void triggerPushNow() {
    if (!_running) return;
    _queuePush();
  }

  void triggerPullNow() {
    if (!_running) return;
    _queuePull();
  }

  void _scheduleNextPull() {
    if (!_running) return;
    _pullTimer?.cancel();
    _pullTimer = Timer(_nextPullDelay(), () {
      _queuePull();
      _scheduleNextPull();
    });
  }

  Duration _nextPullDelay() {
    if (pullJitter == Duration.zero) return pullInterval;
    final maxJitterMs = pullJitter.inMilliseconds.clamp(0, 1 << 31);
    final jitterMs = _random.nextInt(maxJitterMs + 1);
    return pullInterval + Duration(milliseconds: jitterMs);
  }

  void _queuePush() {
    _pushQueued = true;
    _drain();
  }

  void _queuePull() {
    _pullQueued = true;
    _drain();
  }

  void _drain() {
    if (_busy) return;
    if (!_running) return;
    if (!_pushQueued && !_pullQueued) return;

    _busy = true;
    unawaited(_runQueue().whenComplete(() => _busy = false));
  }

  Future<void> _runQueue() async {
    while (_running && (_pullQueued || _pushQueued)) {
      if (_pullQueued) {
        _pullQueued = false;
        await _pullOnce();
        continue;
      }
      if (_pushQueued) {
        _pushQueued = false;
        await _pushOnce();
      }
    }
  }

  Future<void> _pushOnce() async {
    try {
      final config = await loadConfig();
      if (!_running || config == null) return;
      await syncRunner.push(config);
    } catch (_) {
      // Best-effort: avoid crashing the app on transient sync errors.
    }
  }

  Future<void> _pullOnce() async {
    try {
      final config = await loadConfig();
      if (!_running || config == null) return;
      final applied = await syncRunner.pull(config);
      if (applied > 0) {
        _notifyChange();
      }
    } catch (_) {
      // Best-effort: avoid crashing the app on transient sync errors.
    }
  }
}
