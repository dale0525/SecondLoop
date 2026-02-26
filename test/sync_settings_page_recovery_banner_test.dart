import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/vault_recovery_envelope_client.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_secret_store.dart';
import 'package:secondloop/features/settings/sync_settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SyncSecretStore.setProcessSessionKeyForTest(null);
  });

  tearDown(() {
    SyncSecretStore.setProcessSessionKeyForTest(null);
  });

  testWidgets(
      'shows recovery hint banner when envelope exists and sync key is missing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRecoveryEnvelopeJson(
      '{"version":1,"wrapped_sync_key_b64":"banner","kdf":{"version":1}}',
    );
    expect(
      await store.readRecoveryEnvelopeJson(),
      '{"version":1,"wrapped_sync_key_b64":"banner","kdf":{"version":1}}',
    );

    await tester.pumpWidget(
      _wrap(
        backend: _RecoveryBannerBackend(),
        cloudAuth: _FakeCloudAuthController(),
        recoveryClient: _FakeRecoveryEnvelopeClient(),
        store: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sync_recovery_hint_banner')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('sync_recovery_hint_action')),
        findsOneWidget);
  });

  testWidgets('hides recovery hint banner when sync key already exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRecoveryEnvelopeJson(
      '{"version":1,"wrapped_sync_key_b64":"banner","kdf":{"version":1}}',
    );
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 3)));

    await tester.pumpWidget(
      _wrap(
        backend: _RecoveryBannerBackend(),
        cloudAuth: _FakeCloudAuthController(),
        recoveryClient: _FakeRecoveryEnvelopeClient(),
        store: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('sync_recovery_hint_banner')), findsNothing);
  });

  testWidgets('recovery hint action recovers sync key and hides banner',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRecoveryEnvelopeJson(
      '{"version":1,"wrapped_sync_key_b64":"banner","kdf":{"version":1}}',
    );

    final backend = _RecoveryBannerBackend();
    final recoveryClient = _FakeRecoveryEnvelopeClient();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        cloudAuth: _FakeCloudAuthController(),
        recoveryClient: recoveryClient,
        store: store,
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('sync_recovery_passphrase_field')),
      'recover-now',
    );

    await tester.tap(find.byKey(const ValueKey('sync_recovery_hint_action')));
    await tester.pumpAndSettle();

    expect(backend.recoverCalls, 1);
    expect(await store.readSyncKey(), backend.recoveredKey);
    expect(
        find.byKey(const ValueKey('sync_recovery_hint_banner')), findsNothing);
    expect(recoveryClient.putCalls, 1);
  });

  testWidgets(
      'recovery hint action does not fallback to derive when envelope recovery fails',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.default.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRecoveryEnvelopeJson(
      '{"version":1,"wrapped_sync_key_b64":"banner","kdf":{"version":1}}',
    );

    final backend = _RecoveryBannerBackend()..throwOnRecover = true;
    final recoveryClient = _FakeRecoveryEnvelopeClient();

    await tester.pumpWidget(
      _wrap(
        backend: backend,
        cloudAuth: _FakeCloudAuthController(),
        recoveryClient: recoveryClient,
        store: store,
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('sync_recovery_passphrase_field')),
      'wrong-passphrase',
    );
    await tester.tap(find.byKey(const ValueKey('sync_recovery_hint_action')));
    await tester.pumpAndSettle();

    expect(backend.recoverCalls, 1);
    expect(backend.deriveCalls, 0);
    expect(await store.readSyncKey(), isNull);
    expect(recoveryClient.putCalls, 0);
    expect(find.byKey(const ValueKey('sync_recovery_hint_banner')),
        findsOneWidget);
  });
}

Widget _wrap({
  required AppBackend backend,
  required CloudAuthController cloudAuth,
  required VaultRecoveryEnvelopeClient recoveryClient,
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
              vaultRecoveryEnvelopeClient: recoveryClient,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _RecoveryBannerBackend extends TestAppBackend {
  int recoverCalls = 0;
  int createEnvelopeCalls = 0;
  int deriveCalls = 0;
  bool throwOnRecover = false;
  final Uint8List recoveredKey = Uint8List.fromList(List<int>.filled(32, 5));

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    deriveCalls += 1;
    return Uint8List.fromList(List<int>.filled(32, 6));
  }

  @override
  Future<Uint8List> recoverSyncKeyFromEnvelope(
    String envelopeJson,
    String passphrase,
  ) async {
    recoverCalls += 1;
    if (throwOnRecover) {
      throw Exception('invalid_recovery_passphrase');
    }
    return Uint8List.fromList(recoveredKey);
  }

  @override
  Future<String> createSyncRecoveryEnvelope(
    Uint8List syncKey,
    String passphrase,
  ) async {
    createEnvelopeCalls += 1;
    return '{"version":1,"wrapped_sync_key_b64":"new","kdf":{"version":1}}';
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

final class _FakeRecoveryEnvelopeClient extends VaultRecoveryEnvelopeClient {
  _FakeRecoveryEnvelopeClient() : super(httpClient: HttpClient());
  int fetchCalls = 0;
  int putCalls = 0;

  @override
  Future<String?> fetchRecoveryEnvelope({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
  }) async {
    fetchCalls += 1;
    return null;
  }

  @override
  Future<void> putRecoveryEnvelope({
    required String managedVaultBaseUrl,
    required String vaultId,
    required String idToken,
    required String envelopeJson,
  }) async {
    putCalls += 1;
  }
}
