import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'managed vault does not show recovery hint banner even with envelope',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRecoveryEnvelopeJson(
      '{"version":1,"wrapped_sync_key_b64":"banner","kdf":{"version":1}}',
    );

    await tester.pumpWidget(
      _wrap(
        backend: TestAppBackend(),
        cloudAuth: _FakeCloudAuthController(),
        store: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sync_recovery_hint_banner')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sync_recovery_hint_action')),
      findsNothing,
    );
  });

  testWidgets('managed vault hides recovery passphrase field', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    await tester.pumpWidget(
      _wrap(
        backend: TestAppBackend(),
        cloudAuth: _FakeCloudAuthController(),
        store: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sync_recovery_passphrase_field')),
      findsNothing,
    );
  });

  testWidgets('managed vault save re-derives sync key from cloud identity',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 3)));

    final backend = _ManagedVaultKeyPolicyBackend();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        cloudAuth: _FakeCloudAuthController(),
        store: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(backend.deriveCalls, 1);
    expect(backend.lastPassphrase, contains('uid_1'));
    expect(await store.readSyncKey(), backend.derivedSyncKey);
  });
}

Widget _wrap({
  required AppBackend backend,
  required CloudAuthController cloudAuth,
  required SyncConfigStore store,
}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend,
        child: CloudAuthScope(
          controller: cloudAuth,
          child: Scaffold(
            body: SyncSettingsPage(
              configStore: store,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _ManagedVaultKeyPolicyBackend extends TestAppBackend {
  int deriveCalls = 0;
  String? lastPassphrase;
  final Uint8List derivedSyncKey =
      Uint8List.fromList(List<int>.generate(32, (index) => index + 1));

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    deriveCalls += 1;
    lastPassphrase = passphrase;
    return Uint8List.fromList(derivedSyncKey);
  }
}

final class _FakeCloudAuthController implements CloudAuthController {
  @override
  Future<String?> getIdToken() async => 'test-id-token';

  @override
  String? get uid => 'uid_1';

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
