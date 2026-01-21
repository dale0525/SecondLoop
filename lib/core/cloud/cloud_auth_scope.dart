import 'package:flutter/widgets.dart';

import 'cloud_auth_controller.dart';

@immutable
class CloudGatewayConfig {
  const CloudGatewayConfig({required this.baseUrl, required this.modelName});

  final String baseUrl;
  final String modelName;

  static const defaultConfig = CloudGatewayConfig(
    baseUrl: String.fromEnvironment(
      'SECONDLOOP_CLOUD_GATEWAY_BASE_URL',
      defaultValue: '',
    ),
    modelName: 'cloud',
  );
}

class CloudAuthScope extends InheritedWidget {
  const CloudAuthScope({
    required this.controller,
    required super.child,
    this.gatewayConfig = CloudGatewayConfig.defaultConfig,
    super.key,
  });

  final CloudAuthController controller;
  final CloudGatewayConfig gatewayConfig;

  static CloudAuthScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CloudAuthScope>();
  }

  static CloudAuthScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No CloudAuthScope found in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(CloudAuthScope oldWidget) =>
      controller != oldWidget.controller ||
      gatewayConfig.baseUrl != oldWidget.gatewayConfig.baseUrl ||
      gatewayConfig.modelName != oldWidget.gatewayConfig.modelName;
}
