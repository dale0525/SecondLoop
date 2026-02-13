import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/desktop/desktop_boot_prefs.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DesktopBootPrefs.value.value = DesktopBootConfig.defaults;
  });

  test('load falls back to defaults when missing', () async {
    await DesktopBootPrefs.load();

    final config = DesktopBootPrefs.value.value;
    expect(config.startWithSystem, false);
    expect(config.silentStartup, false);
    expect(config.keepRunningInBackground, true);
  });

  test('setters persist values and update notifier', () async {
    await DesktopBootPrefs.setStartWithSystem(true);
    await DesktopBootPrefs.setSilentStartup(true);
    await DesktopBootPrefs.setKeepRunningInBackground(false);

    final config = DesktopBootPrefs.value.value;
    expect(config.startWithSystem, true);
    expect(config.silentStartup, true);
    expect(config.keepRunningInBackground, false);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DesktopBootPrefs.startWithSystemKey), true);
    expect(prefs.getBool(DesktopBootPrefs.silentStartupKey), true);
    expect(prefs.getBool(DesktopBootPrefs.keepRunningInBackgroundKey), false);
  });
}
