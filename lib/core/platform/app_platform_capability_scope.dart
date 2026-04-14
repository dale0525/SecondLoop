import 'package:flutter/material.dart';

import 'app_platform_capabilities.dart';

class AppPlatformCapabilityScope extends InheritedWidget {
  const AppPlatformCapabilityScope({
    required this.capabilities,
    required super.child,
    super.key,
  });

  final AppPlatformCapabilities capabilities;

  static AppPlatformCapabilities of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AppPlatformCapabilityScope>()
            ?.capabilities ??
        AppPlatformCapabilities.native();
  }

  static AppPlatformCapabilities? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppPlatformCapabilityScope>()
        ?.capabilities;
  }

  @override
  bool updateShouldNotify(AppPlatformCapabilityScope oldWidget) {
    return oldWidget.capabilities != capabilities;
  }
}
