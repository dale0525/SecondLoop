import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
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

  testWidgets(
      'Managed-vault pull-only recovery does not upload media when push failed before it',
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
      final backend = _ManagedVaultPullOnlyRecoveryBackend(
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
        while (backend.managedVaultPullCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushCalls, 1);
      expect(backend.managedVaultPullCalls, 1);
      expect(backend.managedVaultUploadAttachmentCalls, 0);
      expect(backend.markUploadedCalls, 0);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault invalid batches persist the background repair block',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultInvalidBatchBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
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
      expect(engine, isNotNull);
      expect(
          engine!.writeGate.value.kind, SyncWriteGateKind.localRepairRequired);
      expect(
        await store.readBackgroundSyncRepairRequired(
          backendType: SyncBackendType.managedVault,
        ),
        isTrue,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Managed-vault media uploads stay pending across pulls until the queue is clear',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 1));
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);
    final pendingScopeId = store.cloudMediaBackupBackfillScopeId(
      SyncConfig.managedVault(
        syncKey: syncKey,
        vaultId: 'vault-1',
        baseUrl: 'https://vault.example.com',
      ),
    );

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultRetryingUploadBackend(
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
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
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
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls < 1 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultUploadAttachmentCalls, 1);
      expect(backend.markUploadedCalls, 0);
      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: pendingScopeId),
        isTrue,
      );

      engine!.triggerPullNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultUploadAttachmentCalls < 2 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPullCalls, greaterThanOrEqualTo(2));
      expect(backend.managedVaultUploadAttachmentCalls, 2);
      expect(backend.markUploadedCalls, 1);
      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: pendingScopeId),
        isFalse,
      );
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets('SyncEngineGate rebuild swaps managed-vault auth token source',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultTokenRecordingBackend();
      final authA = _MutableCloudAuthController(
        uidValue: 'uid-1',
        tokenValue: 'token-a',
      );
      final authB = _MutableCloudAuthController(
        uidValue: 'uid-1',
        tokenValue: 'token-b',
      );
      SyncEngine? engine;

      Widget buildApp(CloudAuthController controller) {
        return MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: controller,
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
      }

      await tester.pumpWidget(buildApp(authA));
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPushTokens.isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushTokens, contains('token-a'));

      await tester.pumpWidget(buildApp(authB));
      await tester.pump();

      engine!.triggerPushNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (!backend.managedVaultPushTokens.contains('token-b') &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushTokens.last, 'token-b');
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'Entitled subscription reopens payment and storage-quota gates, not grace read-only',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ManagedVaultRecordingBackend();
      final subscription = _FakeSubscriptionStatusController(
        SubscriptionStatus.unknown,
      );
      SyncEngine? engine;

      Widget buildApp() {
        return MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: _FakeCloudAuthController(),
                child: SubscriptionScope(
                  controller: subscription,
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
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.pump();

      engine!.writeGate.value =
          const SyncWriteGateState.graceReadOnly(9999999999999);

      subscription.status = SubscriptionStatus.entitled;
      await tester.pump();

      expect(engine!.writeGate.value.kind, SyncWriteGateKind.graceReadOnly);

      engine!.writeGate.value = const SyncWriteGateState.paymentRequired();
      subscription.status = SubscriptionStatus.unknown;
      await tester.pump();
      subscription.status = SubscriptionStatus.entitled;
      await tester.pump();

      expect(engine!.writeGate.value.kind, SyncWriteGateKind.open);

      engine!.writeGate.value = const SyncWriteGateState.storageQuotaExceeded(
        usedBytes: 50,
        limitBytes: 50,
      );
      subscription.status = SubscriptionStatus.unknown;
      await tester.pump();
      subscription.status = SubscriptionStatus.entitled;
      await tester.pump();

      expect(engine!.writeGate.value.kind, SyncWriteGateKind.open);
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
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(Uint8List key) async {
    final pendingCount = _dueBackups
        .where((b) => !_uploaded.contains(b.attachmentSha256))
        .length;
    return CloudMediaBackupSummary(
      pending: pendingCount,
      failed: 0,
      uploaded: _uploaded.length,
    );
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

final class _ManagedVaultPullOnlyRecoveryBackend
    extends _ManagedVaultRecordingBackend {
  _ManagedVaultPullOnlyRecoveryBackend({super.dueBackups});

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
    throw Exception(
      'managed-vault push failed: HTTP 403 {"error":"grace_readonly","grace_until_ms":9999999999999}',
    );
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPullCalls++;
    return 0;
  }
}

final class _ManagedVaultRetryingUploadBackend
    extends _ManagedVaultRecordingBackend {
  _ManagedVaultRetryingUploadBackend({super.dueBackups});

  final Set<String> _failedUploads = <String>{};

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPullCalls++;
    return 0;
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
    if (!_failedUploads.contains(sha256)) {
      _failedUploads.add(sha256);
      throw Exception('transient managed-vault media upload failure');
    }
    return true;
  }

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
  }) async {}

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(Uint8List key) async {
    final pendingCount = _dueBackups
        .where((b) => !_uploaded.contains(b.attachmentSha256))
        .length;
    final failedCount =
        _failedUploads.where((sha256) => !_uploaded.contains(sha256)).length;
    return CloudMediaBackupSummary(
      pending: pendingCount,
      failed: failedCount,
      uploaded: _uploaded.length,
    );
  }
}

final class _ManagedVaultInvalidBatchBackend
    extends _ManagedVaultRecordingBackend {
  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
    throw Exception(
      'managed-vault v2 push failed: HTTP 400 {"error":"invalid_batch","reason":"duplicate_client_op_id"}',
    );
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPullCalls++;
    return 0;
  }
}

final class _ManagedVaultTokenRecordingBackend extends TestAppBackend {
  final List<String> managedVaultPushTokens = <String>[];

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushTokens.add(idToken);
    return 0;
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async =>
      0;
}

final class _MutableCloudAuthController implements CloudAuthController {
  _MutableCloudAuthController({
    required this.uidValue,
    required this.tokenValue,
  });

  final String uidValue;
  final String tokenValue;

  @override
  Future<String?> getIdToken() async => tokenValue;

  @override
  String? get uid => uidValue;

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

final class _FakeSubscriptionStatusController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionStatusController(this._status);

  SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;

  set status(SubscriptionStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
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
