import 'package:flutter/material.dart';

import '../../app/app_shell_style.dart';
import '../../ui/sl_tokens.dart';

class CloudAccountVisualTheme extends StatelessWidget {
  const CloudAccountVisualTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppShellPalette.darkBlue : AppShellPalette.blue;
    final onPrimary = isDark ? const Color(0xFF061A33) : Colors.white;
    final ink = isDark ? AppShellPalette.darkInk : AppShellPalette.ink;
    final muted = isDark ? AppShellPalette.darkMuted : AppShellPalette.muted;
    final line = isDark ? AppShellPalette.darkLine : AppShellPalette.line;
    final panel = isDark ? AppShellPalette.darkPanel : AppShellPalette.panel;
    final soft = isDark ? AppShellPalette.darkSoft : AppShellPalette.soft;
    final surface = isDark ? AppShellPalette.darkSurface : AppShellPalette.soft;
    final selected =
        isDark ? AppShellPalette.darkSelected : AppShellPalette.selected;
    final scheme = theme.colorScheme.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: selected,
      onPrimaryContainer: ink,
      secondary: primary,
      onSecondary: onPrimary,
      secondaryContainer: surface,
      onSecondaryContainer: ink,
      surface: panel,
      surfaceVariant: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      outline: muted,
      outlineVariant: line,
      inversePrimary: primary,
    );
    final cloudTokens = tokens.copyWith(
      background: soft,
      surface: panel,
      surface2: surface,
      border: line,
      borderSubtle: line,
      ring: primary,
      sidebarItemHover: surface,
      sidebarItemActive: selected,
      sidebarItemForeground: muted,
      sidebarItemActiveForeground: ink,
    );
    final extensions = List<ThemeExtension<dynamic>>.of(
      theme.extensions.values.where((extension) => extension is! SlTokens),
    )..add(cloudTokens);
    final controlOverlay = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.pressed)) {
        return primary.withOpacity(0.14);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return primary.withOpacity(0.08);
      }
      return null;
    });
    final checkboxFill = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.selected)) return primary;
      if (states.contains(MaterialState.disabled)) {
        return line.withOpacity(0.48);
      }
      return Colors.transparent;
    });

    return Theme(
      data: theme.copyWith(
        colorScheme: scheme,
        extensions: extensions,
        dividerTheme: theme.dividerTheme.copyWith(
          color: line.withOpacity(0.9),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: MaterialStatePropertyAll(primary),
            overlayColor: controlOverlay,
          ),
        ),
        checkboxTheme: theme.checkboxTheme.copyWith(
          fillColor: checkboxFill,
          checkColor: const MaterialStatePropertyAll(Colors.white),
          overlayColor: controlOverlay,
        ),
      ),
      child: child,
    );
  }
}
