import 'package:flutter/material.dart';

import '../../core/cloud/cloud_usage_client.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/vault_attachments_client.dart';
import '../../core/cloud/vault_usage_client.dart';
import '../../core/subscription/creem_billing_client.dart';
import '../../core/subscription/subscription_scope.dart';
import '../../core/sync/sync_config_store.dart';
import '../../i18n/strings.g.dart';
import '../../web_app/web_formal_settings_scope.dart';
import 'cloud_account_panel.dart';

class CloudAccountPage extends StatelessWidget {
  const CloudAccountPage({
    super.key,
    this.billingClient,
    this.cloudUsageClient,
    this.vaultUsageClient,
    this.vaultAttachmentsClient,
    this.vaultConfigStore,
    this.isWebOverride,
  });

  final BillingClient? billingClient;
  final CloudUsageClient? cloudUsageClient;
  final VaultUsageClient? vaultUsageClient;
  final VaultAttachmentsClient? vaultAttachmentsClient;
  final SyncConfigStore? vaultConfigStore;
  final bool? isWebOverride;

  @override
  Widget build(BuildContext context) {
    final webFormalSettings =
        WebFormalSettingsScope.maybeOf(context)?.dependencies;
    final resolvedBillingClient =
        billingClient ?? webFormalSettings?.billingClient;
    final resolvedCloudUsageClient =
        cloudUsageClient ?? webFormalSettings?.cloudUsageClient;
    final resolvedVaultUsageClient =
        vaultUsageClient ?? webFormalSettings?.vaultUsageClient;
    final resolvedVaultAttachmentsClient =
        vaultAttachmentsClient ?? webFormalSettings?.vaultAttachmentsClient;
    final resolvedVaultConfigStore =
        vaultConfigStore ?? webFormalSettings?.vaultConfigStore;
    final resolvedIsWebOverride =
        isWebOverride ?? webFormalSettings?.isWebOverride;
    Widget panel = CloudAccountPanel(
      billingClient: resolvedBillingClient,
      cloudUsageClient: resolvedCloudUsageClient,
      vaultUsageClient: resolvedVaultUsageClient,
      vaultAttachmentsClient: resolvedVaultAttachmentsClient,
      vaultConfigStore: resolvedVaultConfigStore,
      isWebOverride: resolvedIsWebOverride,
    );

    if (webFormalSettings != null) {
      panel = CloudAuthScope(
        controller: webFormalSettings.cloudAuthController,
        gatewayConfig: webFormalSettings.cloudGatewayConfig,
        child: SubscriptionScope(
          controller: webFormalSettings.subscriptionController,
          child: panel,
        ),
      );
    }

    return Scaffold(
      key: const ValueKey('cloud_account_page_root'),
      appBar: AppBar(
        title: Text(context.t.settings.cloudAccount.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          panel,
        ],
      ),
    );
  }
}
