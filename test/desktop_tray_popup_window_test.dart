import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/desktop/desktop_tray_menu_controller.dart';
import 'package:secondloop/core/desktop/desktop_tray_popup_window.dart';

void main() {
  const labels = DesktopTrayPopupLabels(
    title: 'SecondLoop',
    open: 'Open',
    settings: 'Settings',
    startWithSystem: 'Start with system',
    quit: 'Quit',
    signedIn: 'Signed in',
    aiUsage: 'AI usage',
    storageUsage: 'Storage usage',
  );

  testWidgets('popup renders compact layout and action callbacks',
      (tester) async {
    var openCalls = 0;
    var settingsCalls = 0;
    var quitCalls = 0;
    bool? toggled;

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopTrayPopupWindow(
          labels: labels,
          proUsage: const DesktopTrayProUsage(
            email: 'pro@example.com',
            aiUsagePercent: 62,
            storageUsagePercent: 38,
          ),
          startWithSystemEnabled: true,
          refreshingUsage: false,
          onOpenWindow: () async {
            openCalls += 1;
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
        ),
      ),
    );

    expect(find.text('Signed in: pro@example.com'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('38%'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);
    final compactTiles = tester.widgetList<ListTile>(find.byType(ListTile));
    for (final tile in compactTiles) {
      expect(tile.minTileHeight, 34);
    }
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(ListTile, 'Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Quit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(openCalls, 1);
    expect(settingsCalls, 1);
    expect(quitCalls, 1);
    expect(toggled, false);
  });

  testWidgets('popup shows placeholder usage labels for unknown values',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopTrayPopupWindow(
          labels: labels,
          proUsage: const DesktopTrayProUsage(
            email: 'pro@example.com',
            aiUsagePercent: null,
            storageUsagePercent: null,
          ),
          startWithSystemEnabled: false,
          refreshingUsage: false,
          onOpenWindow: () async {},
          onOpenSettings: () async {},
          onToggleStartWithSystem: (_) async {},
          onQuit: () async {},
        ),
      ),
    );

    expect(find.text('--%'), findsNWidgets(2));
  });
}
