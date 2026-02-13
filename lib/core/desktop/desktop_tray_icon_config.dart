import 'package:flutter/foundation.dart';

final class DesktopTrayIconConfig {
  const DesktopTrayIconConfig({
    required this.assetPath,
    required this.isTemplate,
  });

  final String assetPath;
  final bool isTemplate;
}

DesktopTrayIconConfig trayIconConfigForPlatform(TargetPlatform platform) {
  if (platform == TargetPlatform.windows) {
    return const DesktopTrayIconConfig(
      assetPath: 'assets/icon/tray_icon.ico',
      isTemplate: false,
    );
  }

  return const DesktopTrayIconConfig(
    assetPath: 'assets/icon/tray_icon.png',
    isTemplate: false,
  );
}
