import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../app/theme_palette_prefs.dart';
import '../ui/sl_tokens.dart';

const _webPrimary = Color(0xFF101418);
const _webOnPrimary = Color(0xFFFCFBF8);
const _webBackground = Color(0xFFFCFBF8);
const _webSurface = Color(0xFFFDFCF9);
const _webSurfaceAlt = Color(0xFFF7F3EE);
const _webOutline = Color(0xFFD6CEC5);
const _webOutlineSubtle = Color(0xFFE7DED4);
const _webMuted = Color(0xFF5B616B);
const _webError = Color(0xFFC45E54);
const _webErrorContainer = Color(0xFFF8E8E3);
const _webPeachGlow = Color(0x66F4E8E2);
const _webLavenderGlow = Color(0x7AECE8F7);

ThemeData buildSecondLoopWebTheme({required Locale locale}) {
  final base = AppTheme.light(
    locale: locale,
    palette: AppThemePalette.studio,
  );
  final baseTokens = base.extension<SlTokens>()!;
  final colorScheme = base.colorScheme.copyWith(
    primary: _webPrimary,
    onPrimary: _webOnPrimary,
    primaryContainer: const Color(0xFFECE7DF),
    onPrimaryContainer: _webPrimary,
    secondary: _webMuted,
    onSecondary: _webOnPrimary,
    secondaryContainer: const Color(0xFFF1EBE4),
    onSecondaryContainer: _webPrimary,
    tertiary: const Color(0xFF415061),
    onTertiary: _webOnPrimary,
    tertiaryContainer: const Color(0xFFE8EEF5),
    onTertiaryContainer: _webPrimary,
    error: _webError,
    onError: Colors.white,
    errorContainer: _webErrorContainer,
    onErrorContainer: const Color(0xFF4D1912),
    background: _webBackground,
    onBackground: _webPrimary,
    surface: _webSurface,
    onSurface: _webPrimary,
    surfaceVariant: _webSurfaceAlt,
    onSurfaceVariant: _webMuted,
    outline: _webOutline,
    outlineVariant: _webOutlineSubtle,
    inverseSurface: _webPrimary,
    onInverseSurface: _webOnPrimary,
    inversePrimary: const Color(0xFFE7DED4),
  );
  final tokens = baseTokens.copyWith(
    background: _webBackground,
    surface: const Color(0xF2FFFFFF),
    surface2: _webSurfaceAlt,
    border: _webOutline,
    borderSubtle: _webOutlineSubtle,
    ring: const Color(0xFF415061),
    sidebarBackground: const Color(0xEFFFFFFF),
    sidebarBorder: _webOutline,
    sidebarItemHover: const Color(0x14101418),
    sidebarItemActive: const Color(0x1F101418),
    sidebarItemForeground: _webMuted,
    sidebarItemActiveForeground: _webPrimary,
    radiusSm: 14,
    radiusMd: 18,
    radiusLg: 28,
  );
  final textTheme = _buildTextTheme(base.textTheme, colorScheme);

  return base.copyWith(
    colorScheme: colorScheme,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    scaffoldBackgroundColor: Colors.transparent,
    dividerTheme: const DividerThemeData(
      color: _webOutlineSubtle,
      space: 1,
      thickness: 1,
    ),
    cardTheme: _cardTheme(tokens),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      actionsIconTheme: IconThemeData(color: colorScheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xEFFFFFFF),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 76,
      indicatorColor: const Color(0x16101418),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      labelTextStyle: MaterialStateProperty.resolveWith((states) {
        final selected = states.contains(MaterialState.selected);
        return textTheme.labelMedium?.copyWith(
          color: selected ? _webPrimary : _webMuted,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        );
      }),
      iconTheme: MaterialStateProperty.resolveWith((states) {
        final selected = states.contains(MaterialState.selected);
        return IconThemeData(
          color: selected ? _webPrimary : _webMuted,
          size: 22,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _webSurfaceAlt,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      hintStyle: textTheme.bodyMedium?.copyWith(color: _webMuted),
      border: _outlineBorder(_webOutline, tokens.radiusMd),
      enabledBorder: _outlineBorder(_webOutline, tokens.radiusMd),
      focusedBorder: _outlineBorder(_webPrimary, tokens.radiusMd, width: 1.5),
      errorBorder: _outlineBorder(_webError, tokens.radiusMd),
      focusedErrorBorder:
          _outlineBorder(_webError, tokens.radiusMd, width: 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: const MaterialStatePropertyAll(_webPrimary),
        foregroundColor: const MaterialStatePropertyAll(_webOnPrimary),
        overlayColor: const MaterialStatePropertyAll(Color(0x14101418)),
        elevation: const MaterialStatePropertyAll(0),
        padding: const MaterialStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        shape: MaterialStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
        ),
        textStyle: MaterialStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const MaterialStatePropertyAll(_webPrimary),
        overlayColor: const MaterialStatePropertyAll(Color(0x0F101418)),
        side: const MaterialStatePropertyAll(
          BorderSide(color: _webOutline),
        ),
        backgroundColor: const MaterialStatePropertyAll(Color(0xCCFFFFFF)),
        padding: const MaterialStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        shape: MaterialStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
        ),
        textStyle: MaterialStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const MaterialStatePropertyAll(_webPrimary),
        overlayColor: const MaterialStatePropertyAll(Color(0x0F101418)),
        shape: MaterialStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
        ),
        textStyle: MaterialStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _webPrimary,
      linearTrackColor: _webOutlineSubtle,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: _webPrimary,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: _webOnPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[tokens],
  );
}

class SecondLoopWebAppFrame extends StatelessWidget {
  const SecondLoopWebAppFrame({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _webBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _WebBackdropGlow(
            alignment: Alignment.topLeft,
            color: _webLavenderGlow,
            radius: 0.78,
          ),
          const _WebBackdropGlow(
            alignment: Alignment.topRight,
            color: _webPeachGlow,
            radius: 0.68,
          ),
          const IgnorePointer(
            child: CustomPaint(
              painter: _BackdropGridPainter(
                color: Color(0x080F1418),
                step: 28,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

TextTheme _buildTextTheme(TextTheme base, ColorScheme colorScheme) {
  TextStyle? heading(TextStyle? style, {double? letterSpacing}) {
    return style?.copyWith(
      fontFamily: 'Sora',
      color: colorScheme.onSurface,
      letterSpacing: letterSpacing ?? -0.4,
      height: 1.1,
    );
  }

  TextStyle? body(TextStyle? style) {
    return style?.copyWith(
      fontFamily: 'Inter',
      color: colorScheme.onSurface,
      height: 1.45,
    );
  }

  return base.copyWith(
    displayLarge: heading(base.displayLarge, letterSpacing: -1.4),
    displayMedium: heading(base.displayMedium, letterSpacing: -1.2),
    displaySmall: heading(base.displaySmall, letterSpacing: -1),
    headlineLarge: heading(base.headlineLarge, letterSpacing: -0.9),
    headlineMedium: heading(base.headlineMedium, letterSpacing: -0.8),
    headlineSmall: heading(base.headlineSmall, letterSpacing: -0.7),
    titleLarge: heading(base.titleLarge, letterSpacing: -0.5),
    titleMedium: heading(base.titleMedium, letterSpacing: -0.3)?.copyWith(
      fontWeight: FontWeight.w600,
    ),
    titleSmall: heading(base.titleSmall, letterSpacing: -0.2)?.copyWith(
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: body(base.bodyLarge),
    bodyMedium: body(base.bodyMedium),
    bodySmall: body(base.bodySmall)?.copyWith(color: _webMuted),
    labelLarge: body(base.labelLarge)?.copyWith(fontWeight: FontWeight.w600),
    labelMedium: body(base.labelMedium)?.copyWith(fontWeight: FontWeight.w500),
    labelSmall: body(base.labelSmall)?.copyWith(
      color: _webMuted,
      fontWeight: FontWeight.w500,
    ),
  );
}

dynamic _cardTheme(SlTokens tokens) {
  final dynamic cardTheme = CardTheme(
    color: const Color(0xEFFFFFFF),
    surfaceTintColor: Colors.transparent,
    shadowColor: const Color(0x120F1418),
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      side: const BorderSide(color: _webOutlineSubtle),
    ),
  );

  try {
    return cardTheme.data;
  } on NoSuchMethodError {
    return cardTheme;
  }
}

OutlineInputBorder _outlineBorder(
  Color color,
  double radius, {
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide(color: color, width: width),
  );
}

class _WebBackdropGlow extends StatelessWidget {
  const _WebBackdropGlow({
    required this.alignment,
    required this.color,
    required this.radius,
  });

  final Alignment alignment;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: alignment,
            radius: radius,
            colors: <Color>[
              color,
              color.withOpacity(0),
            ],
            stops: const <double>[0, 1],
          ),
        ),
      ),
    );
  }
}

class _BackdropGridPainter extends CustomPainter {
  const _BackdropGridPainter({
    required this.color,
    required this.step,
  });

  final Color color;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropGridPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.step != step;
  }
}
