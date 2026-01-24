import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

@immutable
class SlTokens extends ThemeExtension<SlTokens> {
  const SlTokens({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.borderSubtle,
    required this.ring,
    required this.sidebarBackground,
    required this.sidebarBorder,
    required this.sidebarItemHover,
    required this.sidebarItemActive,
    required this.sidebarItemForeground,
    required this.sidebarItemActiveForeground,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
  });

  final Color background;
  final Color surface;
  final Color surface2;

  final Color border;
  final Color borderSubtle;
  final Color ring;

  final Color sidebarBackground;
  final Color sidebarBorder;
  final Color sidebarItemHover;
  final Color sidebarItemActive;
  final Color sidebarItemForeground;
  final Color sidebarItemActiveForeground;

  final double radiusSm;
  final double radiusMd;
  final double radiusLg;

  static SlTokens of(BuildContext context) =>
      Theme.of(context).extension<SlTokens>() ?? _fallback;

  static const _fallback = SlTokens(
    background: Color(0xFF0B0B0F),
    surface: Color(0xFF12121A),
    surface2: Color(0xFF171724),
    border: Color(0xFF24243A),
    borderSubtle: Color(0xFF1F1F33),
    ring: Color(0xFFA78BFA),
    sidebarBackground: Color(0xCC12121A),
    sidebarBorder: Color(0x3324243A),
    sidebarItemHover: Color(0x1A6366F1),
    sidebarItemActive: Color(0x266366F1),
    sidebarItemForeground: Color(0xFFB9B9CE),
    sidebarItemActiveForeground: Color(0xFFE7E7F0),
    radiusSm: 10,
    radiusMd: 14,
    radiusLg: 18,
  );

  @override
  SlTokens copyWith({
    Color? background,
    Color? surface,
    Color? surface2,
    Color? border,
    Color? borderSubtle,
    Color? ring,
    Color? sidebarBackground,
    Color? sidebarBorder,
    Color? sidebarItemHover,
    Color? sidebarItemActive,
    Color? sidebarItemForeground,
    Color? sidebarItemActiveForeground,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
  }) {
    return SlTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      ring: ring ?? this.ring,
      sidebarBackground: sidebarBackground ?? this.sidebarBackground,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
      sidebarItemHover: sidebarItemHover ?? this.sidebarItemHover,
      sidebarItemActive: sidebarItemActive ?? this.sidebarItemActive,
      sidebarItemForeground:
          sidebarItemForeground ?? this.sidebarItemForeground,
      sidebarItemActiveForeground:
          sidebarItemActiveForeground ?? this.sidebarItemActiveForeground,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
    );
  }

  @override
  SlTokens lerp(ThemeExtension<SlTokens>? other, double t) {
    if (other is! SlTokens) return this;
    return SlTokens(
      background: Color.lerp(background, other.background, t) ?? background,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surface2: Color.lerp(surface2, other.surface2, t) ?? surface2,
      border: Color.lerp(border, other.border, t) ?? border,
      borderSubtle:
          Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      ring: Color.lerp(ring, other.ring, t) ?? ring,
      sidebarBackground:
          Color.lerp(sidebarBackground, other.sidebarBackground, t) ??
              sidebarBackground,
      sidebarBorder:
          Color.lerp(sidebarBorder, other.sidebarBorder, t) ?? sidebarBorder,
      sidebarItemHover:
          Color.lerp(sidebarItemHover, other.sidebarItemHover, t) ??
              sidebarItemHover,
      sidebarItemActive:
          Color.lerp(sidebarItemActive, other.sidebarItemActive, t) ??
              sidebarItemActive,
      sidebarItemForeground:
          Color.lerp(sidebarItemForeground, other.sidebarItemForeground, t) ??
              sidebarItemForeground,
      sidebarItemActiveForeground: Color.lerp(
            sidebarItemActiveForeground,
            other.sidebarItemActiveForeground,
            t,
          ) ??
          sidebarItemActiveForeground,
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t) ?? radiusSm,
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t) ?? radiusMd,
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t) ?? radiusLg,
    );
  }
}
