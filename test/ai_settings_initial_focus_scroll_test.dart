import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/settings/ai_settings_page.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

Future<double> _pumpPageAndReadOffset(
  WidgetTester tester, {
  AiSettingsSection? focusSection,
  bool focusMediaLocalCapabilityCard = false,
  bool includeBackendScopes = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 480);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  Widget page = MediaQuery(
    data: const MediaQueryData(disableAnimations: true),
    child: AiSettingsPage(
      focusSection: focusSection,
      highlightFocus: true,
      focusMediaLocalCapabilityCard: focusMediaLocalCapabilityCard,
    ),
  );

  if (includeBackendScopes) {
    page = AppBackendScope(
      backend: TestAppBackend(),
      child: SessionScope(
        sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
        lock: () {},
        child: page,
      ),
    );
  }

  await tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
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

  testWidgets(
    'AI settings scrolls to media local capability entry when deep focus is requested',
    (tester) async {
      final offset = await _pumpPageAndReadOffset(
        tester,
        focusSection: AiSettingsSection.mediaUnderstanding,
        focusMediaLocalCapabilityCard: true,
        includeBackendScopes: true,
      );

      expect(offset, greaterThan(0));
    },
  );
}
