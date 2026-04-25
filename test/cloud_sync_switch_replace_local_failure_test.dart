import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/cloud_sync_switch_prompt_gate.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Switching to Cloud does not fallback push after replace-local pull fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });

    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');

    final backend = _ResetThenFailingPullBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
    final syncRunner = _CountingSyncRunner();
    final engine = SyncEngine(
      syncRunner: syncRunner,
      loadConfig: () async => SyncConfig.managedVault(
        syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
        vaultId: 'uid_1',
        baseUrl: 'https://vault.example.com',
      ),
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );
    engine.start();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: SyncEngineScope(
                engine: engine,
                child: CloudAuthScope(
                  controller: cloudAuth,
                  child: SubscriptionScope(
                    controller: subscription,
                    child: CloudSyncSwitchPromptGate(
                      configStore: store,
                      child: const Scaffold(body: Text('home')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Switch'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace this device with remote'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'createSnapshot',
      'resetLocal',
      'syncManagedVaultPull',
      'restoreSnapshot:snapshot-1',
    ]);
    expect(syncRunner.pushCalls, 0);
    expect(syncRunner.pullCalls, 0);
    expect(engine.isRunning, isTrue);
    expect(await store.readBackendType(), SyncBackendType.webdav);
    expect(await store.readRemoteRoot(), 'SecondLoop');

    engine.stopImmediately();
  });
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionController(this._status);

  SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;

  void setStatus(SubscriptionStatus next) {
    _status = next;
    notifyListeners();
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  String? get uid => 'uid_1';

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => 'test-id-token';

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

final class _ResetThenFailingPullBackend extends TestAppBackend {
  final List<String> calls = <String>[];

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 9));

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    calls.add('resetLocal');
  }

  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    calls.add('createSnapshot');
    return 'snapshot-1';
  }

  @override
  Future<void> restoreVaultRollbackSnapshot(
    Uint8List key, {
    required String snapshotPath,
  }) async {
    calls.add('restoreSnapshot:$snapshotPath');
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPull');
    throw StateError('managed_vault_pull_failed');
  }

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPush');
    return 0;
  }
}

final class _CountingSyncRunner implements SyncRunner {
  int pushCalls = 0;
  int pullCalls = 0;

  @override
  Future<int> push(SyncConfig config) async {
    pushCalls += 1;
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    pullCalls += 1;
    return 0;
  }
}
