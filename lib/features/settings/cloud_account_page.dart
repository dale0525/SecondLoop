import 'package:flutter/material.dart';

import '../../core/cloud/cloud_usage_client.dart';
import '../../core/cloud/vault_attachments_client.dart';
import '../../core/cloud/vault_usage_client.dart';
import '../../core/subscription/creem_billing_client.dart';
import '../../core/sync/sync_config_store.dart';
import '../../i18n/strings.g.dart';
import 'cloud_account_panel.dart';

class CloudAccountPage extends StatelessWidget {
  const CloudAccountPage({
    super.key,
    this.billingClient,
    this.cloudUsageClient,
    this.vaultUsageClient,
    this.vaultAttachmentsClient,
    this.vaultConfigStore,
  });

  final BillingClient? billingClient;
  final CloudUsageClient? cloudUsageClient;
  final VaultUsageClient? vaultUsageClient;
  final VaultAttachmentsClient? vaultAttachmentsClient;
  final SyncConfigStore? vaultConfigStore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t.settings.cloudAccount.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CloudAccountPanel(
            billingClient: billingClient,
            cloudUsageClient: cloudUsageClient,
            vaultUsageClient: vaultUsageClient,
            vaultAttachmentsClient: vaultAttachmentsClient,
            vaultConfigStore: vaultConfigStore,
          ),
        ],
      ),
    );
  }
}
