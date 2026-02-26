import 'package:flutter/material.dart';

import 'theme_palette_prefs.dart';

@immutable
final class AppThemeCornerSpec {
  const AppThemeCornerSpec({
    required this.sm,
    required this.md,
    required this.lg,
  });

  final double sm;
  final double md;
  final double lg;
}

@immutable
final class AppThemeStyleSpec {
  const AppThemeStyleSpec({
    required this.seed,
    required this.ring,
    required this.lightBackground,
    required this.lightSurface,
    required this.lightSurface2,
    required this.lightBorder,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkSurface2,
    required this.darkBorder,
    required this.corners,
    required this.lightCardBorderOpacity,
    required this.darkCardBorderOpacity,
    required this.lightIndicatorOpacity,
    required this.darkIndicatorOpacity,
  });

  final Color seed;
  final Color ring;

  final Color lightBackground;
  final Color lightSurface;
  final Color lightSurface2;
  final Color lightBorder;

  final Color darkBackground;
  final Color darkSurface;
  final Color darkSurface2;
  final Color darkBorder;

  final AppThemeCornerSpec corners;
  final double lightCardBorderOpacity;
  final double darkCardBorderOpacity;
  final double lightIndicatorOpacity;
  final double darkIndicatorOpacity;

  Color background(Brightness brightness) {
    return brightness == Brightness.dark ? darkBackground : lightBackground;
  }

  Color surface(Brightness brightness) {
    return brightness == Brightness.dark ? darkSurface : lightSurface;
  }

  Color surface2(Brightness brightness) {
    return brightness == Brightness.dark ? darkSurface2 : lightSurface2;
  }

  Color border(Brightness brightness) {
    return brightness == Brightness.dark ? darkBorder : lightBorder;
  }
}

const kAppThemeStyleSpecs = <AppThemePalette, AppThemeStyleSpec>{
  AppThemePalette.studio: AppThemeStyleSpec(
    seed: Color(0xFF6366F1),
    ring: Color(0xFFA78BFA),
    lightBackground: Color(0xFFF6F7FB),
    lightSurface: Color(0xFFFFFFFF),
    lightSurface2: Color(0xFFF1F3F9),
    lightBorder: Color(0xFFE6E8F0),
    darkBackground: Color(0xFF0B0B0F),
    darkSurface: Color(0xFF12121A),
    darkSurface2: Color(0xFF171724),
    darkBorder: Color(0xFF24243A),
    corners: AppThemeCornerSpec(sm: 10, md: 14, lg: 18),
    lightCardBorderOpacity: 0.9,
    darkCardBorderOpacity: 0.65,
    lightIndicatorOpacity: 0.12,
    darkIndicatorOpacity: 0.18,
  ),
  AppThemePalette.forest: AppThemeStyleSpec(
    seed: Color(0xFF16A34A),
    ring: Color(0xFF86EFAC),
    lightBackground: Color(0xFFF3F8F4),
    lightSurface: Color(0xFFFDFFFD),
    lightSurface2: Color(0xFFEDF6EF),
    lightBorder: Color(0xFFD4E5D8),
    darkBackground: Color(0xFF08110B),
    darkSurface: Color(0xFF0F1A13),
    darkSurface2: Color(0xFF16231B),
    darkBorder: Color(0xFF233628),
    corners: AppThemeCornerSpec(sm: 12, md: 16, lg: 20),
    lightCardBorderOpacity: 0.86,
    darkCardBorderOpacity: 0.72,
    lightIndicatorOpacity: 0.13,
    darkIndicatorOpacity: 0.2,
  ),
  AppThemePalette.ocean: AppThemeStyleSpec(
    seed: Color(0xFF0284C7),
    ring: Color(0xFF67E8F9),
    lightBackground: Color(0xFFF2F8FD),
    lightSurface: Color(0xFFFBFDFF),
    lightSurface2: Color(0xFFEAF3FA),
    lightBorder: Color(0xFFD2E3F0),
    darkBackground: Color(0xFF07111A),
    darkSurface: Color(0xFF101D2A),
    darkSurface2: Color(0xFF162637),
    darkBorder: Color(0xFF244056),
    corners: AppThemeCornerSpec(sm: 14, md: 18, lg: 24),
    lightCardBorderOpacity: 0.82,
    darkCardBorderOpacity: 0.76,
    lightIndicatorOpacity: 0.14,
    darkIndicatorOpacity: 0.24,
  ),
  AppThemePalette.sunset: AppThemeStyleSpec(
    seed: Color(0xFFEA580C),
    ring: Color(0xFFFDBA74),
    lightBackground: Color(0xFFFDF6F1),
    lightSurface: Color(0xFFFFFCFA),
    lightSurface2: Color(0xFFFAECE3),
    lightBorder: Color(0xFFF0D8C9),
    darkBackground: Color(0xFF1A0E09),
    darkSurface: Color(0xFF25150F),
    darkSurface2: Color(0xFF341E15),
    darkBorder: Color(0xFF4A2D22),
    corners: AppThemeCornerSpec(sm: 8, md: 12, lg: 16),
    lightCardBorderOpacity: 0.9,
    darkCardBorderOpacity: 0.66,
    lightIndicatorOpacity: 0.11,
    darkIndicatorOpacity: 0.18,
  ),
  AppThemePalette.monochrome: AppThemeStyleSpec(
    seed: Color(0xFF7A7A7A),
    ring: Color(0xFFBDBDBD),
    lightBackground: Color(0xFFF4F4F4),
    lightSurface: Color(0xFFFCFCFC),
    lightSurface2: Color(0xFFE8E8E8),
    lightBorder: Color(0xFFD4D4D4),
    darkBackground: Color(0xFF0A0A0A),
    darkSurface: Color(0xFF141414),
    darkSurface2: Color(0xFF1F1F1F),
    darkBorder: Color(0xFF343434),
    corners: AppThemeCornerSpec(sm: 10, md: 14, lg: 18),
    lightCardBorderOpacity: 0.9,
    darkCardBorderOpacity: 0.72,
    lightIndicatorOpacity: 0.1,
    darkIndicatorOpacity: 0.18,
  ),
};
