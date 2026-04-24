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

    expect(backend.calls, <String>['resetLocal', 'syncManagedVaultPull:uid_1']);
    expect(await store.readRemoteRoot(), 'uid_1');
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

    expect(backend.calls, <String>['resetLocal', 'syncManagedVaultPull:uid_1']);
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

    expect(backend.calls, <String>['resetLocal', 'syncManagedVaultPull:uid_1']);
    expect(await store.readBackendType(), SyncBackendType.managedVault);
    expect(await store.readRemoteRoot(), 'old_uid');
    expect(await store.readSyncKey(), previousSyncKey);
  });
}

Widget _wrapSettingsPage({
  required SyncConfigStore store,
  required AppBackend backend,
  required CloudAuthController cloudAuth,
  bool cloudSession = false,
}) {
  Widget child = AppBackendScope(
    backend: backend,
    child: CloudAuthScope(
      controller: cloudAuth,
      child: SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: Scaffold(
          body: SyncSettingsPage(configStore: store),
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
  final List<String> calls = <String>[];

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async =>
      Uint8List.fromList(List<int>.filled(32, 9));

  @override
  Future<void> resetVaultDataPreservingLlmProfiles(Uint8List key) async {
    calls.add('resetLocal');
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
  _FakeCloudAuthController({required this.uid});

  @override
  final String uid;

  @override
  Future<String?> getIdToken() async => 'test-id-token';

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
