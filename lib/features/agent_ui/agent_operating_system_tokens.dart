import 'package:flutter/material.dart';

import '../../app/app_shell_style.dart';

@immutable
final class AgentOperatingSystemPalette {
  const AgentOperatingSystemPalette({
    required this.background,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerLow,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.outlineVariant,
    required this.outline,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.muted,
    required this.primaryContainer,
    required this.secondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
  });

  final Color background;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerLow;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color outlineVariant;
  final Color outline;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color muted;
  final Color primaryContainer;
  final Color secondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
}

abstract final class AgentOperatingSystemTokens {
  static const background = Color(0xFFF7F9FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceContainer = Color(0xFFECEEF0);
  static const surfaceContainerLow = Color(0xFFF2F4F6);
  static const surfaceContainerHigh = Color(0xFFE6E8EA);
  static const surfaceContainerHighest = Color(0xFFE0E3E5);
  static const outlineVariant = Color(0xFFC6C6CD);
  static const outline = Color(0xFF76777D);
  static const onSurface = Color(0xFF191C1E);
  static const onSurfaceVariant = Color(0xFF45464D);
  static const muted = Color(0xFF75859D);
  static const primaryContainer = Color(0xFF131B2E);
  static const secondary = Color(0xFF0051D5);
  static const secondaryContainer = Color(0xFF316BF3);
  static const onSecondaryContainer = Color(0xFFFEFCFF);

  static const light = AgentOperatingSystemPalette(
    background: background,
    surface: surface,
    surfaceContainer: surfaceContainer,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    outlineVariant: outlineVariant,
    outline: outline,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    muted: muted,
    primaryContainer: primaryContainer,
    secondary: secondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
  );

  static const dark = AgentOperatingSystemPalette(
    background: AppShellPalette.darkSoft,
    surface: AppShellPalette.darkPanel,
    surfaceContainer: Color(0xFF1B2A40),
    surfaceContainerLow: AppShellPalette.darkSurface,
    surfaceContainerHigh: Color(0xFF20314A),
    surfaceContainerHighest: Color(0xFF2A3D5A),
    outlineVariant: AppShellPalette.darkLine,
    outline: Color(0xFF41516A),
    onSurface: AppShellPalette.darkInk,
    onSurfaceVariant: AppShellPalette.darkMuted,
    muted: Color(0xFF7F8FA8),
    primaryContainer: AppShellPalette.darkSelected,
    secondary: AppShellPalette.darkBlue,
    secondaryContainer: AppShellPalette.darkSelected,
    onSecondaryContainer: Color(0xFFD8E7FF),
  );

  static AgentOperatingSystemPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  static const marginMobile = 16.0;
  static const gutter = 16.0;
  static const radiusSm = 4.0;
  static const radiusMd = 8.0;
  static const radiusLg = 12.0;

  static const labelMd = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
  static const labelLg = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
  static const bodySm = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );
  static const bodyMd = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  );
  static const headlineSm = TextStyle(
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
  static const headlineMd = TextStyle(
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );
  static const code = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
}

extension AgentOperatingSystemPaletteContext on BuildContext {
  AgentOperatingSystemPalette get agentOs =>
      AgentOperatingSystemTokens.of(this);
}
