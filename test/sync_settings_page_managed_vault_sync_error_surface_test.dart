import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
      'Save surfaces managed vault sync errors instead of silent success',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.webdav);
    await store.writeWebdavBaseUrl('https://example.com/dav');
    await store.writeRemoteRoot('SecondLoop');

    final backend = _FailingManagedVaultPullBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: CloudAuthScope(
              controller: _FakeCloudAuthController(),
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
    expect(await store.readBackendType(), SyncBackendType.webdav);

    final backendDropdown =
        tester.widget<DropdownButtonFormField<SyncBackendType>>(
      find.byType(DropdownButtonFormField<SyncBackendType>),
    );
    backendDropdown.onChanged?.call(SyncBackendType.managedVault);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sync_recovery_passphrase_field')),
      findsNothing,
    );

    final saveButton = find.byKey(const ValueKey('sync_save_button'));
    await _ensureListItemVisible(tester, saveButton);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(saveButton) + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(backend.managedVaultPullCalls, 1);
    expect(find.textContaining('Connection failed:'), findsOneWidget);
    expect(find.textContaining('managed_vault_pull_failed'), findsOneWidget);
  });
}

Future<void> _ensureListItemVisible(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  try {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: scrollable,
    );
  } catch (_) {
    await tester.scrollUntilVisible(
      target,
      -180,
      scrollable: scrollable,
    );
  }
  await tester.pumpAndSettle();
}

final class _FailingManagedVaultPullBackend extends TestAppBackend {
  int managedVaultPullCalls = 0;

  @override
  Future<int> syncManagedVaultPull(
    Uint8List key,
    Uint8List syncKey, {
    required String baseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    managedVaultPullCalls += 1;
    throw StateError('managed_vault_pull_failed');
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
