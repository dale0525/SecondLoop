import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/web_app/secondloop_web_app.dart';

void main() {
  testWidgets('SecondLoopWebApp uses website-aligned brand theme',
      (tester) async {
    await tester.pumpWidget(
      SecondLoopWebApp(
        bootstrapLoader: () => Completer<WebAppBootstrapData>().future,
      ),
    );

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final theme = materialApp.theme!;

    expect(theme.colorScheme.primary, const Color(0xFF101418));
    expect(theme.colorScheme.background, const Color(0xFFFCFBF8));
    expect(theme.textTheme.bodyLarge?.fontFamily, 'Inter');
    expect(theme.textTheme.titleLarge?.fontFamily, 'Inter');
    expect(theme.textTheme.titleLarge?.letterSpacing, 0);
    expect(
      theme.textTheme.bodyLarge?.fontVariations?.first.axis,
      'wght',
    );
    expect(theme.inputDecorationTheme.fillColor, const Color(0xFFF7F3EE));
  });

  testWidgets('SecondLoopWebApp wraps pages with a branded app builder',
      (tester) async {
    await tester.pumpWidget(
      SecondLoopWebApp(
        bootstrapLoader: () => Completer<WebAppBootstrapData>().future,
      ),
    );

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(materialApp.builder, isNotNull);
  });
}
