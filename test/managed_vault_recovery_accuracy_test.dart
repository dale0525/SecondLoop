import 'package:flutter/foundation.dart';
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
import 'package:secondloop/core/sync/sync_result.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'managed vault manual upload runs a final pull after recovery retry push',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _GenerationMismatchRecoveryBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: const _FakeCloudAuthController(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: Scaffold(
                  body: SyncSettingsPage(configStore: store),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(ListView);
    final uploadButton = find.widgetWithText(OutlinedButton, 'Upload');
    await tester.dragUntilVisible(
      uploadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(uploadButton);
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>[
        'syncManagedVaultPush',
        'syncManagedVaultPull',
        'syncManagedVaultPush',
        'syncManagedVaultPull',
      ],
    );
    expect(find.text('Uploaded 1 changes'), findsOneWidget);
    expect(find.byKey(const ValueKey('sync_manual_progress')), findsNothing);
  });

  testWidgets('managed vault manual upload reports pull-only recovery refresh',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _GraceReadonlyPullOnlyBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: const _FakeCloudAuthController(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: Scaffold(
                  body: SyncSettingsPage(configStore: store),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(ListView);
    final uploadButton = find.widgetWithText(OutlinedButton, 'Upload');
    await tester.dragUntilVisible(
      uploadButton,
      scrollable,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(uploadButton);
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>[
        'syncManagedVaultPush',
        'syncManagedVaultPull',
      ],
    );
    expect(find.textContaining('Uploaded'), findsNothing);
    expect(find.textContaining('Cloud sync is read-only'), findsOneWidget);
    expect(find.textContaining('Downloaded 2 changes'), findsOneWidget);
  });

  testWidgets('cloud switch flow runs a final pull after recovery retry push',
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

    final backend = _GenerationMismatchRecoveryBackend();
    final subscription =
        _FakeSubscriptionController(SubscriptionStatus.entitled);
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
                  controller: const _FakeCloudAuthController(),
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
    expect(find.text('Choose sync direction'), findsOneWidget);
    await tester.tap(find.text('Merge local and remote'));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>[
        'syncManagedVaultPush',
        'syncManagedVaultPull',
        'syncManagedVaultPush',
        'syncManagedVaultPull',
      ],
    );
    expect(find.textContaining('managed-vault push failed'), findsNothing);
    engine.stop();
  });
}

final class _GenerationMismatchRecoveryBackend extends TestAppBackend {
  final List<String> calls = <String>[];
  var _firstPush = true;

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

  @override
  Future<int> syncManagedVaultPush(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPush');
    if (_firstPush) {
      _firstPush = false;
      throw Exception(
        'managed-vault v2 push failed: HTTP 409 {"error":"generation_mismatch","remote_generation_id":"generation-reset","remote_latest_global_seq":0}',
      );
    }
    return 1;
  }
}

final class _GraceReadonlyPullOnlyBackend extends TestAppBackend {
  final List<String> calls = <String>[];

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPull');
    return 2;
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
    throw Exception(
      'managed-vault push failed: HTTP 403 {"error":"grace_readonly","grace_until_ms":9999999999999}',
    );
  }
}

final class _CountingSyncRunner implements SyncRunner, SyncPullResultRunner {
  @override
  Future<int> pull(SyncConfig config) async => 0;

  @override
  Future<SyncPullResult> pullWithResult(SyncConfig config) async =>
      const SyncPullResult(applied: 0);

  @override
  Future<int> push(SyncConfig config) async => 0;
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionController(this._status);

  final SubscriptionStatus _status;

  @override
  SubscriptionStatus get status => _status;
}

final class _FakeCloudAuthController implements CloudAuthController {
  const _FakeCloudAuthController();

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  String? get uid => 'uid_1';

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
  Future<void> signOut() async {}

  @override
  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
  }) async {}
}
