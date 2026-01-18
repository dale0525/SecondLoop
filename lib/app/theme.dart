import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF0078D4); // Fluent blue
  static const _lightBackground = Color(0xFFF3F3F3); // Fluent neutral canvas
  static const _darkBackground = Color(0xFF202020); // Fluent dark canvas

  static const _radiusMd = 10.0;
  static const _radiusLg = 14.0;

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

    final scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      platform: effectivePlatform,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );

    final surface = scheme.surface;
    final outline = scheme.outlineVariant;

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? _darkBackground : _lightBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? outline.withOpacity(0.5) : outline.withOpacity(0.8),
        space: 1,
        thickness: 1,
      ),
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusLg),
          side: BorderSide(
            color:
                isDark ? outline.withOpacity(0.45) : outline.withOpacity(0.8),
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
        backgroundColor: surface,
        elevation: 0,
        height: 72,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surface : Colors.white.withOpacity(0.9),
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
          borderSide: BorderSide(color: outline.withOpacity(0.75)),
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
