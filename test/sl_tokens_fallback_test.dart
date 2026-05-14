import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/ui/sl_tokens.dart';

void main() {
  testWidgets('SlTokens fallback uses the light agent palette', (tester) async {
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

    expect(tokens.background, const Color(0xFFF7F9FC));
    expect(tokens.surface, Colors.white);
    expect(tokens.surface2, const Color(0xFFF1F5F9));
    expect(tokens.borderSubtle, const Color(0xFFE1E7F0));
  });
}
