import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show Listenable, ValueNotifier;

enum SyncBackendType {
  webdav,
  localDir,
  managedVault,
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

  factory SyncConfig.managedVault({
    required Uint8List syncKey,
    required String vaultId,
    required String baseUrl,
  }) {
    return SyncConfig._(
      backendType: SyncBackendType.managedVault,
      syncKey: syncKey,
      remoteRoot: vaultId,
      baseUrl: baseUrl,
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

enum SyncWriteGateKind {
  open,
  graceReadOnly,
  paymentRequired,
}

final class SyncWriteGateState {
  const SyncWriteGateState._({
    required this.kind,
    required this.graceUntilMs,
  });

  const SyncWriteGateState.open()
      : this._(kind: SyncWriteGateKind.open, graceUntilMs: null);

  const SyncWriteGateState.graceReadOnly(int graceUntilMs)
      : this._(
          kind: SyncWriteGateKind.graceReadOnly,
          graceUntilMs: graceUntilMs,
        );

  const SyncWriteGateState.paymentRequired()
      : this._(kind: SyncWriteGateKind.paymentRequired, graceUntilMs: null);

  final SyncWriteGateKind kind;
  final int? graceUntilMs;

  @override
  bool operator ==(Object other) {
    return other is SyncWriteGateState &&
        other.kind == kind &&
        other.graceUntilMs == graceUntilMs;
  }

  @override
  int get hashCode => Object.hash(kind, graceUntilMs);
}

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

  final ValueNotifier<SyncWriteGateState> writeGate =
      ValueNotifier<SyncWriteGateState>(
    const SyncWriteGateState.open(),
  );

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

  bool _isPushBlocked(int nowMs) {
    final gate = writeGate.value;
    if (gate.kind == SyncWriteGateKind.open) return false;
    if (gate.kind == SyncWriteGateKind.paymentRequired) return true;
    final untilMs = gate.graceUntilMs;
    if (untilMs == null) return true;
    if (nowMs >= untilMs) {
      _setWriteGate(const SyncWriteGateState.open());
      return false;
    }
    return true;
  }

  void _setWriteGate(SyncWriteGateState next) {
    if (writeGate.value == next) return;
    writeGate.value = next;
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
      final backendType = config.backendType;

      if (backendType != SyncBackendType.managedVault) {
        _setWriteGate(const SyncWriteGateState.open());
      } else {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (_isPushBlocked(nowMs)) return;
      }

      await syncRunner.push(config);
      if (backendType == SyncBackendType.managedVault) {
        _setWriteGate(const SyncWriteGateState.open());
      }
    } catch (e) {
      final config = await loadConfig();
      if (config?.backendType != SyncBackendType.managedVault) {
        // Best-effort: avoid crashing the app on transient sync errors.
        return;
      }

      final message = e.toString();
      final status =
          RegExp(r'\bHTTP\s+(\d{3})\b').firstMatch(message)?.group(1);
      final code =
          RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(message)?.group(1);
      final graceUntilRaw =
          RegExp(r'"grace_until_ms"\s*:\s*(\d+)').firstMatch(message)?.group(1);
      final graceUntilMs =
          graceUntilRaw == null ? null : int.tryParse(graceUntilRaw);

      if (status == '403' && code == 'grace_readonly' && graceUntilMs != null) {
        _setWriteGate(SyncWriteGateState.graceReadOnly(graceUntilMs));
      } else if (status == '402') {
        _setWriteGate(const SyncWriteGateState.paymentRequired());
      }

      // Best-effort: avoid crashing the app on transient sync errors.
    }
  }

  Future<void> _pullOnce() async {
    SyncConfig? config;
    try {
      config = await loadConfig();
      if (!_running || config == null) return;
      final applied = await syncRunner.pull(config);

      if (config.backendType == SyncBackendType.managedVault &&
          writeGate.value.kind == SyncWriteGateKind.paymentRequired) {
        _setWriteGate(const SyncWriteGateState.open());
      }

      if (applied > 0) {
        _notifyChange();
      }
    } catch (e) {
      if (config?.backendType != SyncBackendType.managedVault) {
        // Best-effort: avoid crashing the app on transient sync errors.
        return;
      }

      final message = e.toString();
      final status =
          RegExp(r'\bHTTP\s+(\d{3})\b').firstMatch(message)?.group(1);
      if (status == '402') {
        _setWriteGate(const SyncWriteGateState.paymentRequired());
      }

      // Best-effort: avoid crashing the app on transient sync errors.
    }
  }
}
