import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/app/app_shell_style.dart';
import 'package:secondloop/ui/sl_tokens.dart';

void main() {
  testWidgets('SlTokens fallback uses the light SecondLoop palette',
      (tester) async {
    late SlTokens tokens;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            tokens = SlTokens.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(tokens.background, AppShellPalette.soft);
    expect(tokens.surface, AppShellPalette.panel);
    expect(tokens.surface2, AppShellPalette.soft);
    expect(tokens.borderSubtle, AppShellPalette.line);
    expect(tokens.ring, AppShellPalette.blue);
  });
}
