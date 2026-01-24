import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/sl_tokens.dart';

class AppTheme {
  static const _primary = Color(0xFF6366F1); // Indigo
  static const _accent = Color(0xFFA78BFA); // Violet

  static const _lightBackground = Color(0xFFF6F7FB); // Paper
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurface2 = Color(0xFFF1F3F9);
  static const _lightBorder = Color(0xFFE6E8F0);

  static const _darkBackground = Color(0xFF0B0B0F);
  static const _darkSurface = Color(0xFF12121A);
  static const _darkSurface2 = Color(0xFF171724);
  static const _darkBorder = Color(0xFF24243A);

  static const _radiusSm = 10.0;
  static const _radiusMd = 14.0;
  static const _radiusLg = 18.0;

  static ThemeData light({Locale? locale, TargetPlatform? platform}) {
    return _build(
        brightness: Brightness.light, locale: locale, platform: platform);
  }

  static ThemeData dark({Locale? locale, TargetPlatform? platform}) {
    return _build(
        brightness: Brightness.dark, locale: locale, platform: platform);
  }

  static ThemeData _build({
    required Brightness brightness,
    required Locale? locale,
    required TargetPlatform? platform,
  }) {
    final isDark = brightness == Brightness.dark;
    final effectivePlatform = platform ?? defaultTargetPlatform;
    final fontFamily = _primaryFontFamily(effectivePlatform);
    final fontFamilyFallback =
        _fontFamilyFallbackFor(locale, effectivePlatform);

    final scheme = isDark ? _darkScheme() : _lightScheme();
    final tokens = isDark ? _darkTokens() : _lightTokens();

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      platform: effectivePlatform,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      extensions: <ThemeExtension<dynamic>>[
        tokens,
      ],
    );

    final surface = scheme.surface;
    final outline = scheme.outlineVariant;

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? outline.withOpacity(0.55) : outline.withOpacity(0.85),
        space: 1,
        thickness: 1,
      ),
      cardTheme: CardTheme(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
          side: BorderSide(
            color:
                isDark ? outline.withOpacity(0.65) : outline.withOpacity(0.9),
          ),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primary.withOpacity(isDark ? 0.18 : 0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? tokens.surface2 : _lightSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: outline.withOpacity(0.9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide:
              BorderSide(color: outline.withOpacity(isDark ? 0.7 : 0.85)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          padding: const MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusMd),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          padding: const MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusMd),
            ),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radiusMd),
            ),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor:
            isDark ? outline.withOpacity(0.3) : outline.withOpacity(0.5),
      ),
    );
  }

  static ColorScheme _darkScheme() {
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: _primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF1B1B2E),
      onPrimaryContainer: Color(0xFFE7E7F0),
      secondary: _accent,
      onSecondary: _darkBackground,
      secondaryContainer: Color(0xFF25213A),
      onSecondaryContainer: Color(0xFFEDE9FE),
      tertiary: Color(0xFF22D3EE),
      onTertiary: Color(0xFF001216),
      tertiaryContainer: Color(0xFF0B2A33),
      onTertiaryContainer: Color(0xFFCFFAFE),
      error: Color(0xFFF87171),
      onError: Color(0xFF2B0000),
      errorContainer: Color(0xFF3A0B0B),
      onErrorContainer: Color(0xFFFEE2E2),
      background: _darkBackground,
      onBackground: Color(0xFFE7E7F0),
      surface: _darkSurface,
      onSurface: Color(0xFFE7E7F0),
      surfaceVariant: _darkSurface2,
      onSurfaceVariant: Color(0xFFB9B9CE),
      outline: Color(0xFF2F2F4A),
      outlineVariant: _darkBorder,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFE7E7F0),
      onInverseSurface: Color(0xFF101018),
      inversePrimary: Color(0xFF4F46E5),
    );
  }

  static ColorScheme _lightScheme() {
    return const ColorScheme(
      brightness: Brightness.light,
      primary: _primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE0E7FF),
      onPrimaryContainer: Color(0xFF1E1B4B),
      secondary: Color(0xFF7C3AED),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFF3E8FF),
      onSecondaryContainer: Color(0xFF3B0764),
      tertiary: Color(0xFF0891B2),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFCFFAFE),
      onTertiaryContainer: Color(0xFF083344),
      error: Color(0xFFDC2626),
      onError: Colors.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF450A0A),
      background: _lightBackground,
      onBackground: Color(0xFF0F172A),
      surface: _lightSurface,
      onSurface: Color(0xFF0F172A),
      surfaceVariant: _lightSurface2,
      onSurfaceVariant: Color(0xFF475569),
      outline: Color(0xFFD0D4E0),
      outlineVariant: _lightBorder,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFF0F172A),
      onInverseSurface: Color(0xFFF8FAFC),
      inversePrimary: Color(0xFF4F46E5),
    );
  }

  static SlTokens _darkTokens() {
    return const SlTokens(
      background: _darkBackground,
      surface: _darkSurface,
      surface2: _darkSurface2,
      border: _darkBorder,
      borderSubtle: Color(0xFF1F1F33),
      ring: _accent,
      sidebarBackground: Color(0xCC12121A),
      sidebarBorder: Color(0x3324243A),
      sidebarItemHover: Color(0x1A6366F1),
      sidebarItemActive: Color(0x266366F1),
      sidebarItemForeground: Color(0xFFB9B9CE),
      sidebarItemActiveForeground: Color(0xFFE7E7F0),
      radiusSm: _radiusSm,
      radiusMd: _radiusMd,
      radiusLg: _radiusLg,
    );
  }

  static SlTokens _lightTokens() {
    return const SlTokens(
      background: _lightBackground,
      surface: _lightSurface,
      surface2: _lightSurface2,
      border: _lightBorder,
      borderSubtle: Color(0xFFDDE1EC),
      ring: _accent,
      sidebarBackground: Color(0xCCFFFFFF),
      sidebarBorder: Color(0x66E6E8F0),
      sidebarItemHover: Color(0x146366F1),
      sidebarItemActive: Color(0x1F6366F1),
      sidebarItemForeground: Color(0xFF475569),
      sidebarItemActiveForeground: Color(0xFF0F172A),
      radiusSm: _radiusSm,
      radiusMd: _radiusMd,
      radiusLg: _radiusLg,
    );
  }

  static String _primaryFontFamily(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => 'Segoe UI',
      TargetPlatform.macOS => '.SF NS Text',
      TargetPlatform.iOS => '.SF Pro Text',
      TargetPlatform.android => 'Roboto',
      TargetPlatform.linux => 'Ubuntu',
      TargetPlatform.fuchsia => 'Roboto',
    };
  }

  static List<String> _fontFamilyFallbackFor(
    Locale? locale,
    TargetPlatform platform,
  ) {
    final languageCode = locale?.languageCode.toLowerCase();

    final emoji = switch (platform) {
      TargetPlatform.windows => const ['Segoe UI Emoji'],
      TargetPlatform.macOS || TargetPlatform.iOS => const ['Apple Color Emoji'],
      _ => const ['Noto Color Emoji'],
    };

    final base = <String>[
      ...emoji,
      'Segoe UI',
      'Roboto',
      'Noto Sans',
      'Arial',
    ];

    if (languageCode == null || languageCode.isEmpty) {
      return _dedupe(base);
    }

    final localeSpecific = switch (languageCode) {
      'zh' => _dedupe([
          ..._chineseFonts(platform),
          ...base,
        ]),
      'ja' => _dedupe([
          ..._japaneseFonts(platform),
          ...base,
        ]),
      'ko' => _dedupe([
          ..._koreanFonts(platform),
          ...base,
        ]),
      'ar' || 'fa' || 'ur' => _dedupe([
          ..._arabicFonts(platform),
          ...base,
        ]),
      'he' || 'iw' => _dedupe([
          ..._hebrewFonts(platform),
          ...base,
        ]),
      'hi' || 'mr' || 'ne' => _dedupe([
          ..._devanagariFonts(platform),
          ...base,
        ]),
      'bn' => _dedupe([
          ..._bengaliFonts(platform),
          ...base,
        ]),
      'ta' => _dedupe([
          ..._tamilFonts(platform),
          ...base,
        ]),
      'te' => _dedupe([
          ..._teluguFonts(platform),
          ...base,
        ]),
      'ml' => _dedupe([
          ..._malayalamFonts(platform),
          ...base,
        ]),
      'gu' => _dedupe([
          ..._gujaratiFonts(platform),
          ...base,
        ]),
      'kn' => _dedupe([
          ..._kannadaFonts(platform),
          ...base,
        ]),
      'th' => _dedupe([
          ..._thaiFonts(platform),
          ...base,
        ]),
      _ => _dedupe(base),
    };

    return localeSpecific;
  }

  static List<String> _chineseFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'Microsoft JhengHei UI',
          'Microsoft JhengHei',
          'SimSun',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'PingFang SC',
          'PingFang TC',
          'Heiti SC',
          'Heiti TC',
          'Hiragino Sans GB',
        ],
      _ => const [
          'Noto Sans CJK SC',
          'Noto Sans SC',
          'Noto Sans CJK TC',
          'Noto Sans TC',
          'Source Han Sans SC',
          'Source Han Sans TC',
        ],
    };
  }

  static List<String> _japaneseFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Yu Gothic UI',
          'Yu Gothic',
          'Meiryo UI',
          'Meiryo',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Hiragino Sans',
          'Hiragino Kaku Gothic ProN',
          'Hiragino Kaku Gothic Pro',
        ],
      _ => const [
          'Noto Sans JP',
          'Noto Sans CJK JP',
          'Source Han Sans JP',
        ],
    };
  }

  static List<String> _koreanFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Malgun Gothic',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Apple SD Gothic Neo',
        ],
      _ => const [
          'Noto Sans KR',
          'Noto Sans CJK KR',
          'Source Han Sans KR',
        ],
    };
  }

  static List<String> _arabicFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Segoe UI',
          'Tahoma',
          'Arial',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Geeza Pro',
          'Helvetica Neue',
        ],
      _ => const [
          'Noto Sans Arabic',
          'Noto Naskh Arabic',
        ],
    };
  }

  static List<String> _hebrewFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Segoe UI',
          'Arial',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Arial Hebrew',
          'Helvetica Neue',
        ],
      _ => const [
          'Noto Sans Hebrew',
        ],
    };
  }

  static List<String> _devanagariFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Nirmala UI',
          'Segoe UI',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Kohinoor Devanagari',
          'Devanagari Sangam MN',
        ],
      _ => const [
          'Noto Sans Devanagari',
        ],
    };
  }

  static List<String> _bengaliFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Nirmala UI',
          'Segoe UI',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Bangla Sangam MN',
          'Kohinoor Bangla',
        ],
      _ => const [
          'Noto Sans Bengali',
        ],
    };
  }

  static List<String> _tamilFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Nirmala UI',
          'Segoe UI',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Tamil Sangam MN',
          'Kohinoor Tamil',
        ],
      _ => const [
          'Noto Sans Tamil',
        ],
    };
  }

  static List<String> _teluguFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Nirmala UI',
          'Segoe UI',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Telugu Sangam MN',
          'Kohinoor Telugu',
        ],
      _ => const [
          'Noto Sans Telugu',
        ],
    };
  }

  static List<String> _malayalamFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Nirmala UI',
          'Segoe UI',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Malayalam Sangam MN',
          'Kohinoor Malayalam',
        ],
      _ => const [
          'Noto Sans Malayalam',
        ],
    };
  }

  static List<String> _gujaratiFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Nirmala UI',
          'Segoe UI',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Gujarati Sangam MN',
          'Kohinoor Gujarati',
        ],
      _ => const [
          'Noto Sans Gujarati',
        ],
    };
  }

  static List<String> _kannadaFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Nirmala UI',
          'Segoe UI',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Kannada Sangam MN',
          'Kohinoor Kannada',
        ],
      _ => const [
          'Noto Sans Kannada',
        ],
    };
  }

  static List<String> _thaiFonts(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
          'Leelawadee UI',
          'Tahoma',
        ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
          'Thonburi',
          'Sukhumvit Set',
        ],
      _ => const [
          'Noto Sans Thai',
        ],
    };
  }

  static List<String> _dedupe(List<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in items) {
      final key = item.trim();
      if (key.isEmpty) continue;
      if (!seen.add(key)) continue;
      out.add(key);
    }
    return out;
  }
}
