import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_markdown_theme_presets.dart';

void main() {
  test('markdown emphasis styles preserve combined bold italic rendering', () {
    final baseTheme = ThemeData.light().copyWith(
      textTheme: ThemeData.light().textTheme.copyWith(
            bodyMedium: const TextStyle(fontSize: 14),
          ),
    );

    for (final preset in kChatMarkdownThemePresets) {
      final theme = resolveChatMarkdownTheme(preset, baseTheme);
      final styleSheet = theme.buildStyleSheet(baseTheme);

      expect(styleSheet.em?.fontStyle, FontStyle.italic);
      expect(styleSheet.em?.fontWeight, isNull);
      expect(styleSheet.strong?.fontWeight, FontWeight.w700);
      expect(styleSheet.strong?.fontStyle, isNull);
    }
  });
}
