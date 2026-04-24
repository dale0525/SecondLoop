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
  testWidgets('switch-to-cloud stops engine before replacing remote',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeCloudMediaBackupEnabled(false);

    final engine = SyncEngine(
      syncRunner: _CountingSyncRunner(),
      loadConfig: () async => SyncConfig.managedVault(
        syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
        vaultId: 'uid_1',
        baseUrl: 'https://vault.example.com',
      ),
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    )..start();
    bool? engineRunningDuringRemoteClear;
    final backend = _TrackingManagedVaultBackend(
      onClearVault: () {
        engineRunningDuringRemoteClear = engine.isRunning;
      },
    );

    await tester.pumpWidget(_wrapGate(
      store: store,
      backend: backend,
      engine: engine,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace remote with this device'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'syncManagedVaultClearVault',
      'syncManagedVaultPush',
    ]);
    expect(engineRunningDuringRemoteClear, isFalse);
    expect(engine.isRunning, isTrue);

    engine.stopImmediately();
  });

  testWidgets('switch-to-cloud can prompt again after direction is dismissed',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'embeddings_data_consent_v1': false,
    });
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeRemoteRoot('SecondLoop');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeCloudMediaBackupEnabled(false);

    final backend = _TrackingManagedVaultBackend();
    final cloudAuth = _FakeCloudAuthController();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
    final engine = SyncEngine(
      syncRunner: _CountingSyncRunner(),
      loadConfig: () async => null,
      pushDebounce: const Duration(days: 1),
      pullInterval: const Duration(days: 1),
      pullJitter: Duration.zero,
      pullOnStart: false,
    );

    await tester.pumpWidget(_wrapGate(
      store: store,
      backend: backend,
      engine: engine,
      cloudAuth: cloudAuth,
      subscription: subscription,
      gatewayModelName: 'cloud-a',
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(find.text('Choose sync direction'), findsOneWidget);

    Navigator.of(tester.element(find.text('Choose sync direction'))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await tester.pumpWidget(_wrapGate(
      store: store,
      backend: backend,
      engine: engine,
      cloudAuth: cloudAuth,
      subscription: subscription,
      gatewayModelName: 'cloud-b',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Switch to SecondLoop Cloud sync?'), findsOneWidget);
    expect(backend.calls, isEmpty);
  });
}

Widget _wrapGate({
  required SyncConfigStore store,
  required AppBackend backend,
  required SyncEngine engine,
  CloudAuthController? cloudAuth,
  SubscriptionStatusController? subscription,
  String gatewayModelName = 'cloud',
}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: SyncEngineScope(
            engine: engine,
            child: CloudAuthScope(
              controller: cloudAuth ?? _FakeCloudAuthController(),
              gatewayConfig: CloudGatewayConfig(
                baseUrl: 'https://gateway.example.com',
                modelName: gatewayModelName,
              ),
              child: SubscriptionScope(
                controller: subscription ??
                    _FakeSubscriptionController(SubscriptionStatus.entitled),
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
  );
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
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

final class _TrackingManagedVaultBackend extends TestAppBackend {
  _TrackingManagedVaultBackend({this.onClearVault});

  final VoidCallback? onClearVault;
  final List<String> calls = <String>[];

  @override
  Future<void> syncManagedVaultClearVault({
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    onClearVault?.call();
    calls.add('syncManagedVaultClearVault');
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

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPull');
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
