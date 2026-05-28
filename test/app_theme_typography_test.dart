import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/app/theme.dart';

void main() {
  test('AppTheme uses bundled Inter with normal English spacing', () {
    final theme = AppTheme.light(
      locale: const Locale('en'),
      platform: TargetPlatform.macOS,
    );

    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
    expect(theme.primaryTextTheme.bodyMedium?.fontFamily, 'Inter');
    expect(theme.textTheme.titleLarge?.letterSpacing, 0);
    expect(theme.textTheme.bodyMedium?.letterSpacing, 0);
    expect(theme.textTheme.labelLarge?.letterSpacing, 0);
  });

  test('AppTheme keeps CJK fallback fonts for zh-CN', () {
    final theme = AppTheme.light(
      locale: const Locale('zh', 'CN'),
      platform: TargetPlatform.macOS,
    );

    final fallback = theme.textTheme.bodyMedium?.fontFamilyFallback;
    expect(fallback, isNotNull);
    expect(fallback, contains('PingFang SC'));
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
  });
}
