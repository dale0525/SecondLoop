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
      'managed-vault blob repair queue keeps pending uploads set even when cloud summary is empty',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    final syncKey = Uint8List.fromList(List<int>.filled(32, 7));
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(syncKey);
    await store.writeCloudMediaBackupEnabled(true);
    await store.writeCloudMediaBackupWifiOnly(true);
    final scopeId = store.syncStateScopeId(
      SyncConfig.managedVault(
        syncKey: syncKey,
        vaultId: 'vault-1',
        baseUrl: 'https://vault.example.com',
      ),
    );
    SyncEngine? engine;

    final oldConnectivity = ConnectivityPlatform.instance;
    ConnectivityPlatform.instance = _FakeConnectivityPlatform.wifi();
    try {
      final backend = _BlobRepairPendingManagedVaultBackend();

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
        while ((backend.managedVaultPushCalls == 0 ||
                backend.managedVaultPullCalls == 0) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(backend.managedVaultPushCalls, 1);
      expect(backend.managedVaultPullCalls, greaterThanOrEqualTo(1));
      expect(engine, isNotNull);

      await store.writeManagedVaultMediaUploadPending(
        scopeId: scopeId,
        pending: false,
      );

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
      expect(
        await store.readManagedVaultMediaUploadPending(scopeId: scopeId),
        isTrue,
      );
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

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _results;
}

final class _BlobRepairPendingManagedVaultBackend extends TestAppBackend {
  int managedVaultPushCalls = 0;
  int managedVaultPullCalls = 0;

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPushCalls++;
    return 1;
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

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(Uint8List key) async {
    return const CloudMediaBackupSummary(
      pending: 0,
      failed: 0,
      uploaded: 0,
    );
  }

  @override
  Future<int> syncManagedVaultBlobRepairQueueDepth({
    required String baseUrl,
    required String vaultId,
  }) async {
    return 1;
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  Future<String?> getIdToken() async => 'token';

  @override
  String? get uid => 'vault-1';

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
