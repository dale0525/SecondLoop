import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/desktop/desktop_tray_icon_config.dart';

void main() {
  test('macOS tray icon uses png asset and non-template mode', () {
    final config = trayIconConfigForPlatform(TargetPlatform.macOS);
    expect(config.assetPath, 'assets/icon/tray_icon.png');
    expect(config.isTemplate, false);
  });

  test('windows tray icon uses ico asset', () {
    final config = trayIconConfigForPlatform(TargetPlatform.windows);
    expect(config.assetPath, 'assets/icon/tray_icon.ico');
    expect(config.isTemplate, false);
  });
}
