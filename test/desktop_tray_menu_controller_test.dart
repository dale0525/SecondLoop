import 'package:flutter_test/flutter_test.dart';
import 'package:menu_base/menu_base.dart';

import 'package:secondloop/core/desktop/desktop_tray_menu_controller.dart';

void main() {
  const labels = DesktopTrayMenuLabels(
    open: 'Open',
    hide: 'Hide',
    settings: 'Settings',
    startWithSystem: 'Start with system',
    quit: 'Quit',
    signedIn: 'Signed in',
    aiUsage: 'AI usage',
    storageUsage: 'Storage usage',
  );

  test('build menu includes pro details when available', () {
    final controller = DesktopTrayMenuController(
      onOpenWindow: () async {},
      onHideWindow: () async {},
      onOpenSettings: () async {},
      onToggleStartWithSystem: (_) async {},
      onQuit: () async {},
    );

    final menu = controller.buildMenu(
      labels: labels,
      state: const DesktopTrayMenuState(
        startWithSystemEnabled: true,
        proUsage: DesktopTrayProUsage(
          email: 'pro@example.com',
          aiUsagePercent: 62,
          storageUsagePercent: 38,
        ),
      ),
    );

    final items = menu.items ?? const <MenuItem>[];
    expect(
        items.where((e) => e.label == 'Signed in: pro@example.com').length, 1);
    expect(
      items.where((e) => e.label?.startsWith('AI usage') ?? false).length,
      1,
    );
    expect(
      items.where((e) => e.label?.startsWith('Storage usage') ?? false).length,
      1,
    );

    final startWithSystem =
        menu.getMenuItem(kDesktopTrayMenuStartWithSystemKey);
    expect(startWithSystem, isNotNull);
    expect(startWithSystem!.type, 'checkbox');
    expect(startWithSystem.checked, true);
  });

  test('build menu hides pro details when not entitled', () {
    final controller = DesktopTrayMenuController(
      onOpenWindow: () async {},
      onHideWindow: () async {},
      onOpenSettings: () async {},
      onToggleStartWithSystem: (_) async {},
      onQuit: () async {},
    );

    final menu = controller.buildMenu(
      labels: labels,
      state: const DesktopTrayMenuState(startWithSystemEnabled: false),
    );

    final items = menu.items ?? const <MenuItem>[];
    expect(
        items.where((e) => e.label?.startsWith('Signed in') ?? false), isEmpty);
    expect(
      items.where((e) => e.label?.startsWith('AI usage') ?? false),
      isEmpty,
    );
    expect(
      items.where((e) => e.label?.startsWith('Storage usage') ?? false),
      isEmpty,
    );
  });

  test('menu click dispatches actions including startup toggle', () async {
    var openCalls = 0;
    var hideCalls = 0;
    var settingsCalls = 0;
    var quitCalls = 0;
    bool? toggled;

    final controller = DesktopTrayMenuController(
      onOpenWindow: () async {
        openCalls += 1;
      },
      onHideWindow: () async {
        hideCalls += 1;
      },
      onOpenSettings: () async {
        settingsCalls += 1;
      },
      onToggleStartWithSystem: (enabled) async {
        toggled = enabled;
      },
      onQuit: () async {
        quitCalls += 1;
      },
    );

    await controller.onMenuItemClick(
      MenuItem(key: kDesktopTrayMenuOpenKey),
      startWithSystemEnabled: false,
    );
    await controller.onMenuItemClick(
      MenuItem(key: kDesktopTrayMenuHideKey),
      startWithSystemEnabled: false,
    );
    await controller.onMenuItemClick(
      MenuItem(key: kDesktopTrayMenuSettingsKey),
      startWithSystemEnabled: false,
    );
    await controller.onMenuItemClick(
      MenuItem(key: kDesktopTrayMenuStartWithSystemKey),
      startWithSystemEnabled: false,
    );
    await controller.onMenuItemClick(
      MenuItem(key: kDesktopTrayMenuQuitKey),
      startWithSystemEnabled: false,
    );

    expect(openCalls, 1);
    expect(hideCalls, 1);
    expect(settingsCalls, 1);
    expect(toggled, true);
    expect(quitCalls, 1);
  });

  test('progress formatting includes ascii bar and percent', () {
    expect(formatTrayUsageProgress(0), '[----------] 0%');
    expect(formatTrayUsageProgress(62), '[######----] 62%');
    expect(formatTrayUsageProgress(100), '[##########] 100%');
    expect(formatTrayUsageProgress(null), '[----------] --%');
  });
}
