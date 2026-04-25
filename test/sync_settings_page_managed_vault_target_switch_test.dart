import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/platform/app_platform_capabilities.dart';
import 'package:secondloop/core/platform/app_platform_capability_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Managed Vault save prompts when vault id changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('old_uid');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _TrackingManagedVaultBackend();
    final cloudAuth = _FakeCloudAuthController(uid: 'uid_1');

    await tester.pumpWidget(_wrapSettingsPage(
      store: store,
      backend: backend,
      cloudAuth: cloudAuth,
    ));
    await tester.pumpAndSettle();

    await _tapSave(tester);

    expect(find.text('Choose sync direction'), findsOneWidget);
    await tester.tap(find.text('Replace this device with remote'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'createSnapshot',
      'resetLocal',
      'syncManagedVaultPull:uid_1',
      'deleteSnapshot:test-vault-rollback-snapshot',
    ]);
    expect(await store.readRemoteRoot(), 'uid_1');
  });

  testWidgets('Managed Vault save prompts when cloud server changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('uid_1');
    await store.writeManagedVaultBaseUrl('https://old-vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _TrackingManagedVaultBackend();
    final cloudAuth = _FakeCloudAuthController(uid: 'uid_1');

    await tester.pumpWidget(_wrapSettingsPage(
      store: store,
      backend: backend,
      cloudAuth: cloudAuth,
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Sync method').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Cloud server address (advanced)',
      ),
      'https://new-vault.example.com',
    );
    await tester.pumpAndSettle();

    await _tapSave(tester);

    expect(find.text('Choose sync direction'), findsOneWidget);
  });

  testWidgets('Cloud session save prompts when signed-in vault changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('old_uid');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _TrackingManagedVaultBackend();
    final cloudAuth = _FakeCloudAuthController(uid: 'uid_1');

    await tester.pumpWidget(_wrapSettingsPage(
      store: store,
      backend: backend,
      cloudAuth: cloudAuth,
      cloudSession: true,
    ));
    await tester.pumpAndSettle();

    await _tapSave(tester);

    expect(find.text('Choose sync direction'), findsOneWidget);
    await tester.tap(find.text('Replace this device with remote'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'createSnapshot',
      'resetLocal',
      'syncManagedVaultPull:uid_1',
      'deleteSnapshot:test-vault-rollback-snapshot',
    ]);
    expect(await store.readRemoteRoot(), 'uid_1');
  });

  testWidgets('Managed Vault replace-local save rolls back after pull fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('old_uid');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    final previousSyncKey = Uint8List.fromList(List<int>.filled(32, 7));
    await store.writeSyncKey(previousSyncKey);

    final backend = _FailingPullManagedVaultBackend();
    final cloudAuth = _FakeCloudAuthController(uid: 'uid_1');

    await tester.pumpWidget(_wrapSettingsPage(
      store: store,
      backend: backend,
      cloudAuth: cloudAuth,
    ));
    await tester.pumpAndSettle();

    await _tapSave(tester);

    expect(find.text('Choose sync direction'), findsOneWidget);
    await tester.tap(find.text('Replace this device with remote'));
    await tester.pumpAndSettle();

    expect(backend.calls, <String>[
      'createSnapshot',
      'resetLocal',
      'syncManagedVaultPull:uid_1',
      'restoreSnapshot:test-vault-rollback-snapshot',
      'deleteSnapshot:test-vault-rollback-snapshot',
    ]);
    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(await store.readRemoteRoot(), 'old_uid');
    expect(await store.readSyncKey(), previousSyncKey);
  });

  testWidgets(
      'Managed Vault replace-remote save requires auth without fallback sync',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('old_uid');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final backend = _TrackingManagedVaultBackend();
    final cloudAuth = _FakeCloudAuthController(
      uid: 'uid_1',
      idToken: null,
    );
    final runner = _RecordingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: store.loadConfiguredSync,
      pullOnStart: false,
      pushDebounce: Duration.zero,
    );

    await tester.pumpWidget(_wrapSettingsPage(
      store: store,
      backend: backend,
      cloudAuth: cloudAuth,
      engine: engine,
    ));
    await tester.pumpAndSettle();

    await _tapSave(tester);

    expect(find.text('Choose sync direction'), findsOneWidget);
    await tester.tap(find.text('Replace remote with this device'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(backend.calls, isEmpty);
    expect(runner.calls, isEmpty);
    expect(await store.readRemoteRoot(), 'old_uid');
    expect(engine.isRunning, isFalse);
  });

  testWidgets('Managed Vault switch stops running engine before remote reset',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('old_uid');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 7)));

    final runner = _RecordingSyncRunner();
    final engine = SyncEngine(
      syncRunner: runner,
      loadConfig: store.loadConfiguredSync,
      pullOnStart: false,
      pushDebounce: Duration.zero,
    )..start();
    bool? engineRunningDuringRemoteClear;
    final backend = _TrackingManagedVaultBackend(
      onClearVault: () {
        engineRunningDuringRemoteClear = engine.isRunning;
      },
    );
    final cloudAuth = _FakeCloudAuthController(uid: 'uid_1');

    await tester.pumpWidget(_wrapSettingsPage(
      store: store,
      backend: backend,
      cloudAuth: cloudAuth,
      engine: engine,
    ));
    await tester.pumpAndSettle();

    await _tapSave(tester);

    expect(find.text('Choose sync direction'), findsOneWidget);
    await tester.tap(find.text('Replace remote with this device'));
    await tester.pumpAndSettle();

    expect(
      backend.calls,
      <String>[
        'syncManagedVaultClearVault:uid_1',
        'syncManagedVaultPush:uid_1'
      ],
    );
    expect(engineRunningDuringRemoteClear, isFalse);
    expect(engine.isRunning, isTrue);

    engine.stopImmediately();
  });
}

Widget _wrapSettingsPage({
  required SyncConfigStore store,
  required AppBackend backend,
  required CloudAuthController cloudAuth,
  bool cloudSession = false,
  SyncEngine? engine,
}) {
  Widget child = AppBackendScope(
    backend: backend,
    child: CloudAuthScope(
      controller: cloudAuth,
      child: SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: SyncEngineScope(
          engine: engine,
          child: Scaffold(
            body: SyncSettingsPage(configStore: store),
          ),
        ),
      ),
    ),
  );

  if (cloudSession) {
    child = AppPlatformCapabilityScope(
      capabilities: AppPlatformCapabilities.webCloud(),
      child: child,
    );
  }

  return wrapWithI18n(MaterialApp(home: child));
}

Future<void> _tapSave(WidgetTester tester) async {
  final saveButton = find.byKey(const ValueKey('sync_save_button'));
  await tester.scrollUntilVisible(
    saveButton,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
  await tester.pumpAndSettle();
}

final class _TrackingManagedVaultBackend extends TestAppBackend {
  _TrackingManagedVaultBackend({this.onClearVault});

  final VoidCallback? onClearVault;
  final List<String> calls = <String>[];

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 9));

  @override
  Future<String?> createVaultRollbackSnapshot(Uint8List key) async {
    calls.add('createSnapshot');
    return 'test-vault-rollback-snapshot';
  }

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    calls.add('resetLocal');
  }

  @override
  Future<void> restoreVaultRollbackSnapshot(
    Uint8List key, {
    required String snapshotPath,
  }) async {
    calls.add('restoreSnapshot:$snapshotPath');
  }

  @override
  Future<void> deleteVaultRollbackSnapshot({
    required String snapshotPath,
  }) async {
    calls.add('deleteSnapshot:$snapshotPath');
  }

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPull:$vaultId');
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
    calls.add('syncManagedVaultPush:$vaultId');
    return 0;
  }

  @override
  Future<void> syncManagedVaultClearVault({
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    onClearVault?.call();
    calls.add('syncManagedVaultClearVault:$vaultId');
  }
}

final class _FailingPullManagedVaultBackend
    extends _TrackingManagedVaultBackend {
  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    calls.add('syncManagedVaultPull:$vaultId');
    throw StateError('managed_vault_pull_failed');
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  _FakeCloudAuthController({required this.uid, this.idToken = 'test-id-token'});

  @override
  final String uid;

  final String? idToken;

  @override
  Future<String?> getIdToken() async => idToken;

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

final class _RecordingSyncRunner implements SyncRunner {
  final List<String> calls = <String>[];

  @override
  Future<int> push(SyncConfig config) async {
    calls.add('push:${config.remoteRoot}');
    return 0;
  }

  @override
  Future<int> pull(SyncConfig config) async {
    calls.add('pull:${config.remoteRoot}');
    return 0;
  }
}
