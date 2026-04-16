import 'package:flutter/widgets.dart';

import '../core/cloud/cloud_usage_client.dart';
import '../core/cloud/cloud_auth_controller.dart';
import '../core/cloud/cloud_auth_scope.dart';
import '../core/cloud/vault_attachments_client.dart';
import '../core/cloud/vault_usage_client.dart';
import '../core/subscription/creem_billing_client.dart';
import '../core/subscription/subscription_scope.dart';
import '../core/sync/sync_config_store.dart';

@immutable
final class WebFormalSettingsDependencies {
  const WebFormalSettingsDependencies({
    required this.billingClient,
    required this.cloudUsageClient,
    required this.vaultUsageClient,
    required this.vaultAttachmentsClient,
    required this.vaultConfigStore,
    required this.cloudAuthController,
    required this.cloudGatewayConfig,
    required this.subscriptionController,
    required this.isWebOverride,
  });

  final BillingClient billingClient;
  final CloudUsageClient cloudUsageClient;
  final VaultUsageClient vaultUsageClient;
  final VaultAttachmentsClient vaultAttachmentsClient;
  final SyncConfigStore vaultConfigStore;
  final CloudAuthController cloudAuthController;
  final CloudGatewayConfig cloudGatewayConfig;
  final SubscriptionStatusController subscriptionController;
  final bool isWebOverride;
}

final class WebFormalSettingsScope extends InheritedWidget {
  const WebFormalSettingsScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final WebFormalSettingsDependencies dependencies;

  static WebFormalSettingsScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WebFormalSettingsScope>();
  }

  @override
  bool updateShouldNotify(WebFormalSettingsScope oldWidget) {
    final oldDependencies = oldWidget.dependencies;
    return dependencies.billingClient != oldDependencies.billingClient ||
        dependencies.cloudUsageClient != oldDependencies.cloudUsageClient ||
        dependencies.vaultUsageClient != oldDependencies.vaultUsageClient ||
        dependencies.vaultAttachmentsClient !=
            oldDependencies.vaultAttachmentsClient ||
        dependencies.vaultConfigStore != oldDependencies.vaultConfigStore ||
        dependencies.cloudAuthController !=
            oldDependencies.cloudAuthController ||
        dependencies.cloudGatewayConfig.baseUrl !=
            oldDependencies.cloudGatewayConfig.baseUrl ||
        dependencies.cloudGatewayConfig.modelName !=
            oldDependencies.cloudGatewayConfig.modelName ||
        dependencies.subscriptionController !=
            oldDependencies.subscriptionController ||
        dependencies.isWebOverride != oldDependencies.isWebOverride;
  }
}
