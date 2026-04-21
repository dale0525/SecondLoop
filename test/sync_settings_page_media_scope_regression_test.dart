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
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'managed-vault media actions use the derived sync scope before config is saved',
      (tester) async {
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.example.com',
    );
    await store.writeBackendType(SyncBackendType.managedVault);

    final derivedSyncKey = Uint8List.fromList(List<int>.filled(32, 9));
    final backend = _ManagedVaultMediaScopeBackend(derivedSyncKey);
    final expectedScopeId = store.syncStateScopeId(
      SyncConfig.managedVault(
        syncKey: derivedSyncKey,
        vaultId: 'vault-1',
        baseUrl: 'https://vault.example.com',
      ),
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('en'),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: CloudAuthScope(
                controller: const _FakeCloudAuthController(),
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

    await _ensureVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Queue existing files'),
    );
    await tester
        .tap(find.widgetWithText(OutlinedButton, 'Queue existing files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(backend.deriveSyncKeyCalls, 1);
    expect(backend.backfillScopeIds, <String?>[expectedScopeId]);
    expect(backend.summaryScopeIds.last, expectedScopeId);
  });
}

Future<void> _ensureVisible(WidgetTester tester, Finder target) async {
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

final class _ManagedVaultMediaScopeBackend extends AppBackend {
  _ManagedVaultMediaScopeBackend(this.derivedSyncKey);

  final Uint8List derivedSyncKey;
  int deriveSyncKeyCalls = 0;
  final List<String?> backfillScopeIds = <String?>[];
  final List<String?> summaryScopeIds = <String?>[];

  @override
  Future<Uint8List> deriveSyncKey(String passphrase) async {
    deriveSyncKeyCalls += 1;
    return Uint8List.fromList(derivedSyncKey);
  }

  @override
  Future<int> backfillCloudMediaBackupImages(
    Uint8List key, {
    required String desiredVariant,
    required int nowMs,
    String? scopeId,
  }) async {
    backfillScopeIds.add(scopeId);
    return 1;
  }

  @override
  Future<CloudMediaBackupSummary> cloudMediaBackupSummary(
    Uint8List key, {
    String? scopeId,
  }) async {
    summaryScopeIds.add(scopeId);
    return const CloudMediaBackupSummary(
      pending: 0,
      failed: 0,
      uploaded: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeCloudAuthController implements CloudAuthController {
  const _FakeCloudAuthController();

  @override
  String? get uid => 'vault-1';

  @override
  String? get email => 'vault-1@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'token';

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
