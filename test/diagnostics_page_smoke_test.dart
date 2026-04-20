import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/subscription/creem_billing_client.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/core/sync/sync_diagnostics.dart';
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/update/app_update_service.dart';
import 'package:secondloop/core/update/update_event_log.dart';
import 'package:secondloop/features/settings/diagnostics_page.dart';
import 'package:secondloop/features/settings/settings_page.dart';
import 'package:secondloop/web_app/web_formal_settings_scope.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Settings can open diagnostics page', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final diagnosticsFinder =
        find.byKey(const ValueKey('settings_diagnostics'));
    await tester.scrollUntilVisible(
      diagnosticsFinder,
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(diagnosticsFinder);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('diagnostics_page')), findsOneWidget);
  });

  testWidgets('Diagnostics JSON does not expose cloud gateway URL', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final diagnosticsFinder =
        find.byKey(const ValueKey('settings_diagnostics'));
    await tester.scrollUntilVisible(
      diagnosticsFinder,
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(diagnosticsFinder);
    await tester.pumpAndSettle();

    final diagnosticsJsonText = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(const ValueKey('diagnostics_page')),
        matching: find.byType(SelectableText),
      ),
    );
    final diagnosticsJson =
        jsonDecode(diagnosticsJsonText.data!) as Map<String, Object?>;
    final cloud = diagnosticsJson['cloud'] as Map<String, Object?>;

    expect(cloud.containsKey('gateway_base_url'), isFalse);
  });

  testWidgets('Diagnostics JSON includes last sync log', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore();
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-user-1');
    await store.writeManagedVaultBaseUrl('https://vault.example.com');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));
    await store.writeBackgroundSyncResult(
      const SyncBackgroundResult(
        backendType: SyncBackendType.managedVault,
        direction: SyncBackgroundDirection.pull,
        status: SyncBackgroundResultStatus.failure,
        timestampMs: 1730000000000,
        statusCode: 429,
        errorCode: 'rate_limited',
        errorMessage: 'managed-vault pull failed: HTTP 429',
        userMessage: 'Sync is being throttled. Retrying later.',
        retryCount: 2,
        durationMs: 520,
      ),
      backendType: SyncBackendType.managedVault,
      scopeId: store.syncStateScopeIdForFields(
        backendType: SyncBackendType.managedVault,
        baseUrl: 'https://vault.example.com',
        remoteRoot: 'vault-user-1',
        syncKey: Uint8List.fromList(List<int>.filled(32, 1)),
      ),
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final diagnosticsFinder =
        find.byKey(const ValueKey('settings_diagnostics'));
    await tester.scrollUntilVisible(
      diagnosticsFinder,
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(diagnosticsFinder);
    await tester.pumpAndSettle();

    final diagnosticsJsonText = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(const ValueKey('diagnostics_page')),
        matching: find.byType(SelectableText),
      ),
    );
    final diagnosticsJson =
        jsonDecode(diagnosticsJsonText.data!) as Map<String, Object?>;
    final sync = diagnosticsJson['sync'] as Map<String, Object?>;
    final lastSyncLog = sync['last_sync_log'] as Map<String, Object?>?;

    expect(lastSyncLog, isNotNull);
    expect(lastSyncLog!['backendType'], 'managedvault');
    expect(lastSyncLog['direction'], 'pull');
    expect(lastSyncLog['status'], 'failure');
    expect(lastSyncLog['statusCode'], 429);
  });

  testWidgets(
      'Diagnostics JSON reuses web formal settings sync store for managed vault base URL',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://vault.runtime.example',
    );
    await store.writeBackendType(SyncBackendType.managedVault);
    await store.writeRemoteRoot('vault-user-1');
    await store.writeSyncKey(Uint8List.fromList(List<int>.filled(32, 1)));

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            MaterialApp(
              home: WebFormalSettingsScope(
                dependencies: WebFormalSettingsDependencies(
                  billingClient: _FakeBillingClient(),
                  cloudUsageClient: CloudUsageClient(),
                  vaultUsageClient: VaultUsageClient(),
                  vaultAttachmentsClient: VaultAttachmentsClient(),
                  vaultConfigStore: store,
                  cloudAuthController: _FakeCloudAuthController(),
                  cloudGatewayConfig: const CloudGatewayConfig(
                    baseUrl: '',
                    modelName: 'cloud',
                  ),
                  subscriptionController: _FakeSubscriptionController(),
                  isWebOverride: true,
                ),
                child: const Scaffold(body: DiagnosticsPage()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final diagnosticsJsonText = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(const ValueKey('diagnostics_page')),
        matching: find.byType(SelectableText),
      ),
    );
    final diagnosticsJson =
        jsonDecode(diagnosticsJsonText.data!) as Map<String, Object?>;
    final sync = diagnosticsJson['sync'] as Map<String, Object?>;

    expect(sync['backend'], 'managedVault');
    expect(sync['base_url'], 'https://vault.runtime.example');
    expect(sync['remote_root'], 'vault-user-1');
  });

  testWidgets('Diagnostics JSON includes recent update logs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final logger = SharedPrefsUpdateEventLogger();
    await logger.record(
      UpdateEventRecord(
        type: UpdateEventType.updateAvailable,
        timestampUtc: DateTime.utc(2026, 3, 14, 12),
        platform: AppUpdatePlatform.windows,
        currentVersion: '1.0.0+1',
        latestTag: 'v1.1.0',
        installMode: AppUpdateInstallMode.seamlessRestart,
        message: 'staged_ready',
      ),
    );

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final diagnosticsFinder =
        find.byKey(const ValueKey('settings_diagnostics'));
    await tester.scrollUntilVisible(
      diagnosticsFinder,
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(diagnosticsFinder);
    await tester.pumpAndSettle();

    final diagnosticsJsonText = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(const ValueKey('diagnostics_page')),
        matching: find.byType(SelectableText),
      ),
    );
    final diagnosticsJson =
        jsonDecode(diagnosticsJsonText.data!) as Map<String, Object?>;
    final updateLogs = diagnosticsJson['update_logs'] as List<Object?>;
    final firstLog = updateLogs.single as Map<String, Object?>;

    expect(firstLog['type'], 'updateAvailable');
    expect(firstLog['platform'], 'windows');
    expect(firstLog['latestTag'], 'v1.1.0');
    expect(firstLog['installMode'], 'seamlessRestart');
  });

  testWidgets('Diagnostics page no longer shows update actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      AppBackendScope(
        backend: TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: wrapWithI18n(
            const MaterialApp(home: Scaffold(body: SettingsPage())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final diagnosticsFinder =
        find.byKey(const ValueKey('settings_diagnostics'));
    await tester.scrollUntilVisible(
      diagnosticsFinder,
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(diagnosticsFinder);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('diagnostics_check_updates')), findsNothing);
    expect(
        find.byKey(const ValueKey('diagnostics_apply_update')), findsNothing);
  });
}

final class _FakeBillingClient implements BillingClient {
  @override
  Future<void> openCheckout() async {}

  @override
  Future<void> openPortal() async {}
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  @override
  SubscriptionStatus get status => SubscriptionStatus.unknown;
}

final class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  @override
  String? get uid => null;

  @override
  String? get email => null;

  @override
  bool? get emailVerified => null;

  @override
  Future<String?> getIdToken() async => null;

  @override
  Future<void> refreshUserInfo() async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

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
