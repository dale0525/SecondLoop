import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  testWidgets(
      'managed-vault pull does not upload media for a new scope before that scope has pushed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKeyA = Uint8List.fromList(List<int>.filled(32, 1));
    final syncKeyB = Uint8List.fromList(List<int>.filled(32, 2));
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKeyA);
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ScopeAwareManagedVaultBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: CloudAuthScope(
                controller: const _StubCloudAuthController(),
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
        while ((backend.managedVaultPushCalls == 0 ||
                backend.managedVaultPullCalls == 0) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushCalls, greaterThanOrEqualTo(1));
      expect(backend.managedVaultPullCalls, greaterThanOrEqualTo(1));
      expect(backend.managedVaultUploadAttachmentCalls, 0);

      await store.writeRemoteRoot('vault-2');
      await store.writeSyncKey(syncKeyB);

      engine!.triggerPullNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (backend.managedVaultPullCalls < 2 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPullCalls, greaterThanOrEqualTo(2));
      expect(backend.managedVaultUploadAttachmentCalls, 0);
      expect(backend.uploadedVaultIds, isEmpty);
    } finally {
      ConnectivityPlatform.instance = oldConnectivity;
    }
  });

  testWidgets(
      'managed-vault write gate is rehydrated when switching from a blocked scope to a clean scope',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKeyA = Uint8List.fromList(List<int>.filled(32, 1));
    final syncKeyB = Uint8List.fromList(List<int>.filled(32, 2));
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKeyA);
    await store.writeCloudMediaBackupEnabled(false);

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _ScopedWriteGateBackend();
      SyncEngine? engine;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 9)),
              lock: () {},
              child: CloudAuthScope(
                controller: const _StubCloudAuthController(),
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
        while (backend.blockedPushCalls == 0 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(engine, isNotNull);
      expect(backend.blockedPushCalls, greaterThanOrEqualTo(1));
      expect(
        engine!.writeGate.value.kind,
        SyncWriteGateKind.localRepairRequired,
      );

      await store.writeRemoteRoot('vault-2');
      await store.writeSyncKey(syncKeyB);
      await tester.pump();

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      engine!.triggerPushNow();
      await tester.pump();

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (
            backend.cleanPushCalls == 0 && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(engine!.writeGate.value.kind, SyncWriteGateKind.open);
      expect(backend.cleanPushCalls, 1);
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

final class _ScopeAwareManagedVaultBackend extends TestAppBackend {
  int managedVaultPushCalls = 0;
  int managedVaultPullCalls = 0;
  int managedVaultUploadAttachmentCalls = 0;

  final List<String> uploadedVaultIds = <String>[];
  String _activeVaultId = 'vault-1';

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
    _activeVaultId = vaultId;
    return 0;
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
    _activeVaultId = vaultId;
    return 0;
  }

  @override
  Future<List<CloudMediaBackup>> listDueCloudMediaBackups(
    Uint8List key, {
    required int nowMs,
    int limit = 100,
    String? scopeId,
  }) async {
    if (_activeVaultId != 'vault-2') {
      return const <CloudMediaBackup>[];
    }
    return const <CloudMediaBackup>[
      CloudMediaBackup(
        attachmentSha256: 'vault-2-attachment',
        desiredVariant: 'original',
        byteLen: 0,
        status: 'pending',
        attempts: 0,
        nextRetryAtMs: null,
        lastError: null,
        updatedAtMs: 0,
      ),
    ];
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) async {
    if (_activeVaultId != 'vault-2') {
      return const CloudMediaBackupSummary(pending: 0, failed: 0, uploaded: 0);
    }
    return const CloudMediaBackupSummary(pending: 1, failed: 0, uploaded: 0);
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
    uploadedVaultIds.add(vaultId);
    return true;
  }

  @override
  Future<void> markCloudMediaBackupUploaded(
    Uint8List key, {
    required String attachmentSha256,
    required int nowMs,
    String? scopeId,
  }) async {}

  @override
  Future<void> markCloudMediaBackupFailed(
    Uint8List key, {
    required String attachmentSha256,
    required int attempts,
    required int nextRetryAtMs,
    required String lastError,
    required int nowMs,
    String? scopeId,
  }) async {}

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
    String? scopeId,
  }) async =>
      0;
}

final class _ScopedWriteGateBackend extends TestAppBackend {
  int blockedPushCalls = 0;
  int cleanPushCalls = 0;

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    if (vaultId == 'vault-1') {
      blockedPushCalls++;
      throw StateError(
        'managed-vault v2 push failed: HTTP 400 {"error":"invalid_batch","reason":"duplicate_client_op_id"}',
      );
    }
    cleanPushCalls++;
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

final class _StubCloudAuthController implements CloudAuthController {
  const _StubCloudAuthController();

  @override
  Future<String?> getIdToken() async => 'token';

  @override
  String? get uid => 'uid';

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
