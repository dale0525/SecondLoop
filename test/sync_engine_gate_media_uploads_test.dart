import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  testWidgets('Media uploads off => sync uses ops-only push (WebDAV)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend();

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.webdavPushCalls == 0 &&
            backend.webdavPushOpsOnlyCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.webdavPushCalls, 0);
      expect(backend.webdavPushOpsOnlyCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets('Media uploads on => uploads due items automatically (WebDAV)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend(
        dueBackups: [
          const CloudMediaBackup(
            attachmentSha256: 'a',
            desiredVariant: 'original',
            byteLen: 0,
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            updatedAtMs: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.webdavUploadAttachmentCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.webdavPushOpsOnlyCalls, greaterThanOrEqualTo(1));
      expect(backend.webdavUploadAttachmentCalls, 1);
      expect(backend.markUploadedCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'SyncEngineGate flushes pending push when app pauses during blocking pull',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _BlockingLifecycleBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineGate(
                child: Builder(
                  builder: (context) {
                    engine = SyncEngineScope.maybeOf(context);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while ((backend.webdavPullCalls == 0 ||
                backend.webdavPushOpsOnlyCalls == 0) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(engine, isNotNull);
      final baselinePushCalls = backend.webdavPushOpsOnlyCalls;
      expect(baselinePushCalls, greaterThanOrEqualTo(1));

      backend.blockNextPull();
      engine!.triggerPullNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!backend.hasBlockedPull && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(backend.hasBlockedPull, isTrue);

      engine!.notifyLocalMutation();
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      backend.completeBlockedPull(applied: 0);
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.webdavPushOpsOnlyCalls == baselinePushCalls &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.webdavPushOpsOnlyCalls, baselinePushCalls + 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets('Media uploads on => auto-backfills cloud media queue once',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeWebdavUsername('u');
    await store.writeWebdavPassword('p');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _RecordingBackend();

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const SyncEngineGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.cloudMediaBackfillCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.cloudMediaBackfillCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault auto sync uses full push and waits for pull before media uploads',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultRecordingBackend(
        dueBackups: [
          const CloudMediaBackup(
            attachmentSha256: 'a',
            desiredVariant: 'original',
            byteLen: 0,
            status: 'pending',
            attempts: 0,
            nextRetryAtMs: null,
            lastError: null,
            updatedAtMs: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: const SyncEngineGate(child: SizedBox.shrink()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPushCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushCalls, 1);
      expect(backend.managedVaultPushOpsOnlyCalls, 0);
      expect(backend.managedVaultUploadAttachmentCalls, 0);

      backend.completePull(applied: 0);

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPullCalls, 1);
      expect(backend.managedVaultUploadAttachmentCalls, 1);
      expect(backend.markUploadedCalls, 1);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });
}

final class _FakeConnectivityPlatform extends ConnectivityPlatform {
  _FakeConnectivityPlatform._(this._results);

  factory _FakeConnectivityPlatform.wifi() {
    return _FakeConnectivityPlatform._(
      const <ConnectivityResult>[ConnectivityResult.wifi],
    );
  }

  final List<ConnectivityResult> _results;

  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _results;
}

final class _BlockingLifecycleBackend extends TestAppBackend {
  int webdavPushOpsOnlyCalls = 0;
  int webdavPullCalls = 0;

  bool _blockNextPull = false;
  bool hasBlockedPull = false;
  Completer<int>? _pullCompleter;

  void blockNextPull() {
    _blockNextPull = true;
    hasBlockedPull = false;
  }

  void completeBlockedPull({required int applied}) {
    final completer = _pullCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(applied);
  }

  @override
  Future<int> syncWebdavPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    webdavPushOpsOnlyCalls++;
    return 0;
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) {
    webdavPullCalls++;
    if (!_blockNextPull) {
      return Future<int>.value(0);
    }

    _blockNextPull = false;
    hasBlockedPull = true;
    _pullCompleter = Completer<int>();
    return _pullCompleter!.future;
  }
}

final class _RecordingBackend extends TestAppBackend {
  _RecordingBackend({List<CloudMediaBackup>? dueBackups})
      : _dueBackups = List<CloudMediaBackup>.from(dueBackups ?? const []);

  int webdavPushCalls = 0;
  int webdavPushOpsOnlyCalls = 0;
  int webdavUploadAttachmentCalls = 0;
  int markUploadedCalls = 0;
  int cloudMediaBackfillCalls = 0;

  final List<CloudMediaBackup> _dueBackups;
  final Set<String> _uploaded = <String>{};

  @override
  Future<int> syncWebdavPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    webdavPushCalls++;
    return 0;
  }

  @override
  Future<int> syncWebdavPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async {
    webdavPushOpsOnlyCalls++;
    return 0;
  }

  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
  }) async {
    return _dueBackups
        .where((b) => !_uploaded.contains(b.attachmentSha256))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
  }) async {
    markUploadedCalls++;
    _uploaded.add(attachmentSha256);
  }

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {
    // ignored
  }

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
  }) async {
    cloudMediaBackfillCalls++;
    return 0;
  }

  @override
  Future<bool> syncWebdavUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
    required String sha256,
  }) async {
    webdavUploadAttachmentCalls++;
    return true;
  }

  @override
  Future<int> syncWebdavPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    String? username,
    String? password,
    required String remoteRoot,
  }) async =>
      0;
}

final class _ManagedVaultRecordingBackend extends _RecordingBackend {
  _ManagedVaultRecordingBackend({super.dueBackups});

  int managedVaultPushCalls = 0;
  int managedVaultPushOpsOnlyCalls = 0;
  int managedVaultPullCalls = 0;
  int managedVaultUploadAttachmentCalls = 0;

  Completer<int>? _pullCompleter;

  void completePull({required int applied}) {
    final completer = _pullCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(applied);
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
    return 0;
  }

  @override
  Future<int> syncManagedVaultPushOpsOnly(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushOpsOnlyCalls++;
    return 0;
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) {
    managedVaultPullCalls++;
    _pullCompleter = Completer<int>();
    return _pullCompleter!.future;
  }

  @override
  Future<bool> syncManagedVaultUploadAttachmentBytes(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
    required String sha256,
  }) async {
    managedVaultUploadAttachmentCalls++;
    return true;
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  Future<String?> getIdToken() async => 'test-id-token';

  @override
  String? get uid => 'uid-1';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
