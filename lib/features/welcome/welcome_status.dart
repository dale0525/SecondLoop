import 'package:flutter/widgets.dart';

import '../../core/ai/ai_routing.dart';
import '../../core/cloud/cloud_auth_scope.dart';
import '../../core/cloud/runtime_connection_store.dart';
import '../../core/cloud/runtime_profile.dart';
import '../../core/subscription/subscription_scope.dart';

typedef WelcomeGuideStatusLoader = Future<WelcomeGuideStatus> Function(
  BuildContext context,
);

class WelcomeGuideStatus {
  const WelcomeGuideStatus({
    required this.runtimeMode,
  });

  final WelcomeGuideRuntimeMode runtimeMode;
}

enum WelcomeGuideRuntimeMode {
  notConfigured,
  managedPro,
  selfManaged,
}

Future<WelcomeGuideStatus> loadWelcomeGuideStatus(BuildContext context) async {
  final cloudScope = CloudAuthScope.maybeOf(context);
  final uid = cloudScope?.controller.uid?.trim() ?? '';
  final apiBaseUrl = cloudScope?.gatewayConfig.baseUrl.trim() ?? '';
  final subscriptionStatus =
      SubscriptionScope.maybeOf(context)?.status ?? SubscriptionStatus.unknown;

  try {
    final connection = await RuntimeConnectionStore().loadConnection();
    if (connection != null) {
      if (connection.profile.runtimeMode == CloudRuntimeMode.managedPro &&
          subscriptionStatus != SubscriptionStatus.entitled) {
        return const WelcomeGuideStatus(
          runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
        );
      }

      return WelcomeGuideStatus(
        runtimeMode: switch (connection.profile.runtimeMode) {
          CloudRuntimeMode.managedPro => WelcomeGuideRuntimeMode.managedPro,
          CloudRuntimeMode.selfManaged => WelcomeGuideRuntimeMode.selfManaged,
        },
      );
    }
  } catch (_) {
    // Fall through to account-scope detection.
  }

  if (uid.isNotEmpty &&
      apiBaseUrl.isNotEmpty &&
      subscriptionStatus == SubscriptionStatus.entitled) {
    return const WelcomeGuideStatus(
      runtimeMode: WelcomeGuideRuntimeMode.managedPro,
    );
  }

  return const WelcomeGuideStatus(
    runtimeMode: WelcomeGuideRuntimeMode.notConfigured,
  );
}
