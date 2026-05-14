import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/subscription/creem_billing_client.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/features/settings/cloud_account_page.dart';
import 'package:secondloop/i18n/strings.g.dart';
import 'package:secondloop/web_app/web_app_gate.dart';
import 'package:secondloop/web_app/web_entry_intent.dart';
import 'package:secondloop/web_app/web_formal_settings_scope.dart';

import '../test_i18n.dart';
import '../test_backend.dart';

void main() {
  testWidgets(
      'settings cloud account page reuses web billing adapters from the gate',
      (tester) async {
    LocaleSettings.setLocale(AppLocale.en);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));
    SharedPreferences.setMockInitialValues({});
    final service = _FakeWebAppService(
      subscription: WebSubscriptionState.entitled,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: WebAppGate(
            entryIntent: WebEntryIntent.manage,
            authController: _FakeCloudAuthController(
              uid: 'uid-1',
              email: 'user@example.com',
            ),
            service: service,
            defaultBackendBuilder: () => _FakeUnlockedWebBackend(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cloudAccountLink = find.text(t.settings.agentUi.links.cloudAccount);
    await tester.ensureVisible(cloudAccountLink);
    await tester.tap(cloudAccountLink);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cloud_manage_subscription')));
    await tester.pumpAndSettle();

    expect(service.openPortalCount, 1);
  });

  testWidgets(
      'cloud account page restores signed-in state from web formal settings scope',
      (tester) async {
    final authController = _FakeCloudAuthController(
      uid: 'uid-1',
      email: 'user@example.com',
    );
    final subscriptionController = _FakeSubscriptionController(
      SubscriptionStatus.entitled,
      canManageSubscription: true,
    );

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: WebFormalSettingsScope(
            dependencies: WebFormalSettingsDependencies(
              billingClient: _FakeBillingClient(),
              cloudUsageClient: CloudUsageClient(),
              vaultUsageClient: VaultUsageClient(),
              vaultAttachmentsClient: VaultAttachmentsClient(),
              vaultConfigStore: SyncConfigStore(
                managedVaultDefaultBaseUrl: 'https://web.secondloop.invalid/',
              ),
              cloudAuthController: authController,
              cloudGatewayConfig: const CloudGatewayConfig(
                baseUrl: 'https://web.secondloop.invalid/',
                modelName: 'cloud',
              ),
              subscriptionController: subscriptionController,
              isWebOverride: true,
            ),
            child: const CloudAccountPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Signed in as'), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud_sign_in')), findsNothing);
  });
}

final class _FakeUnlockedWebBackend extends TestAppBackend {
  @override
  Future<bool> isMasterPasswordSet() async => false;
}

final class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  _FakeCloudAuthController({
    required this.uid,
    required this.email,
  });

  @override
  final String? uid;

  @override
  final String? email;

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => uid == null ? null : 'token';

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

final class _FakeWebAppService extends WebAppService {
  _FakeWebAppService({required this.subscription});

  final WebSubscriptionState subscription;
  int openPortalCount = 0;

  @override
  Future<WebSubscriptionSnapshot> fetchSubscription({
    required String idToken,
  }) async {
    return WebSubscriptionSnapshot(
      state: subscription,
      canManageSubscription: subscription == WebSubscriptionState.entitled,
    );
  }

  @override
  Future<void> openPortal({required String idToken}) async {
    openPortalCount += 1;
  }

  @override
  Future<WebUsageSummary?> fetchUsage({required String idToken}) async {
    return const WebUsageSummary(
      askAiUsagePercent: 0,
      embeddingsUsagePercent: 0,
      resetAtMs: null,
    );
  }
}

final class _FakeBillingClient implements BillingClient {
  @override
  Future<void> openCheckout() async {}

  @override
  Future<void> openPortal() async {}
}

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionDetailsController {
  _FakeSubscriptionController(
    this.status, {
    this.canManageSubscription,
  });

  @override
  final SubscriptionStatus status;

  @override
  final bool? canManageSubscription;
}
