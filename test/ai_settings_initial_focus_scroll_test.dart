import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/settings/ai_settings_page.dart';

import 'test_i18n.dart';

Future<double> _pumpPageAndReadOffset(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 480);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  const page = MediaQuery(
    data: MediaQueryData(disableAnimations: true),
    child: AiSettingsPage(highlightFocus: true),
  );

  await tester.pumpWidget(
    wrapWithI18n(
      const MaterialApp(
        home: page,
      ),
    ),
  );

  for (var i = 0; i < 40; i += 1) {
    await tester.pump(const Duration(milliseconds: 32));
  }

  final scrollable =
      tester.state<ScrollableState>(find.byType(Scrollable).first);
  return scrollable.position.pixels;
}

void main() {
  testWidgets('AI settings stays at top without a focus target',
      (tester) async {
    final offset = await _pumpPageAndReadOffset(tester);
    expect(offset, 0);
  });
}
