import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/ai/ai_routing.dart';
import 'package:secondloop/core/cloud/cloud_auth_controller.dart';
import 'package:secondloop/core/cloud/cloud_auth_scope.dart';
import 'package:secondloop/core/cloud/cloud_usage_client.dart';
import 'package:secondloop/core/cloud/vault_attachments_client.dart';
import 'package:secondloop/core/cloud/vault_usage_client.dart';
import 'package:secondloop/core/subscription/creem_billing_client.dart';
import 'package:secondloop/core/subscription/subscription_scope.dart';
import 'package:secondloop/core/sync/sync_config_store.dart';
import 'package:secondloop/web_app/web_formal_settings_scope.dart';

void main() {
  test('web formal settings scope only notifies when dependency fields change',
      () {
    final billingClient = _FakeBillingClient();
    final cloudUsageClient = CloudUsageClient();
    final vaultUsageClient = VaultUsageClient();
    final vaultAttachmentsClient = VaultAttachmentsClient();
    final vaultConfigStore = SyncConfigStore(
      managedVaultDefaultBaseUrl: 'https://web.secondloop.invalid/',
    );
    final cloudAuthController = _FakeCloudAuthController();
    final subscriptionController =
        _FakeSubscriptionController(SubscriptionStatus.entitled);

    final baseDependencies = WebFormalSettingsDependencies(
      billingClient: billingClient,
      cloudUsageClient: cloudUsageClient,
      vaultUsageClient: vaultUsageClient,
      vaultAttachmentsClient: vaultAttachmentsClient,
      vaultConfigStore: vaultConfigStore,
      cloudAuthController: cloudAuthController,
      cloudGatewayConfig: const CloudGatewayConfig(
        baseUrl: 'https://web.secondloop.invalid/',
        modelName: 'cloud',
      ),
      subscriptionController: subscriptionController,
      isWebOverride: true,
    );

    final unchangedScope = WebFormalSettingsScope(
      dependencies: WebFormalSettingsDependencies(
        billingClient: billingClient,
        cloudUsageClient: cloudUsageClient,
        vaultUsageClient: vaultUsageClient,
        vaultAttachmentsClient: vaultAttachmentsClient,
        vaultConfigStore: vaultConfigStore,
        cloudAuthController: cloudAuthController,
        cloudGatewayConfig: const CloudGatewayConfig(
          baseUrl: 'https://web.secondloop.invalid/',
          modelName: 'cloud',
        ),
        subscriptionController: subscriptionController,
        isWebOverride: true,
      ),
      child: const SizedBox.shrink(),
    );
    final baseScope = WebFormalSettingsScope(
      dependencies: baseDependencies,
      child: const SizedBox.shrink(),
    );

    expect(unchangedScope.updateShouldNotify(baseScope), isFalse);

    final changedScope = WebFormalSettingsScope(
      dependencies: WebFormalSettingsDependencies(
        billingClient: billingClient,
        cloudUsageClient: cloudUsageClient,
        vaultUsageClient: vaultUsageClient,
        vaultAttachmentsClient: vaultAttachmentsClient,
        vaultConfigStore: SyncConfigStore(
          managedVaultDefaultBaseUrl: 'https://other.secondloop.invalid/',
        ),
        cloudAuthController: cloudAuthController,
        cloudGatewayConfig: const CloudGatewayConfig(
          baseUrl: 'https://web.secondloop.invalid/',
          modelName: 'cloud',
        ),
        subscriptionController: subscriptionController,
        isWebOverride: true,
      ),
      child: const SizedBox.shrink(),
    );

    expect(changedScope.updateShouldNotify(baseScope), isTrue);
  });
}

final class _FakeBillingClient implements BillingClient {
  @override
  Future<void> openCheckout() async {}

  @override
  Future<void> openPortal() async {}
}

final class _FakeCloudAuthController extends ChangeNotifier
    implements ObservableCloudAuthController, CloudPasswordRecoveryController {
  @override
  String? get uid => 'uid-1';

  @override
  String? get email => 'user@example.com';

  @override
  bool? get emailVerified => true;

  @override
  Future<String?> getIdToken() async => 'token';

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

final class _FakeSubscriptionController extends ChangeNotifier
    implements SubscriptionStatusController {
  _FakeSubscriptionController(this.status);

  @override
  final SubscriptionStatus status;
}
