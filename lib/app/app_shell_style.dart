import 'package:flutter/material.dart';

abstract final class AppShellStyle {
  static const desktopShellMaxWidth = double.infinity;
  static const desktopShellSidebarWidth = 230.0;
  static const desktopShellMargin = 12.0;
  static const desktopShellRadius = 16.0;
}

abstract final class AppShellPalette {
  static const blue = Color(0xFF0B5CF6);
  static const ink = Color(0xFF101936);
  static const muted = Color(0xFF63708A);
  static const line = Color(0xFFE1E7F0);
  static const panel = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF7F9FC);
  static const selected = Color(0xFFEAF1FF);

  static const darkBlue = Color(0xFF6EA8FF);
  static const darkInk = Color(0xFFEAF1FF);
  static const darkMuted = Color(0xFF9AA8BD);
  static const darkLine = Color(0xFF26364D);
  static const darkPanel = Color(0xFF101A2B);
  static const darkSurface = Color(0xFF162235);
  static const darkSoft = Color(0xFF08111F);
  static const darkSelected = Color(0xFF123A6E);
}

final class AppShellLayoutScope extends InheritedWidget {
  const AppShellLayoutScope({
    required this.desktopWorkbench,
    required super.child,
    super.key,
  });

  final bool desktopWorkbench;

  static bool? desktopWorkbenchOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppShellLayoutScope>()
        ?.desktopWorkbench;
  }

  @override
  bool updateShouldNotify(AppShellLayoutScope oldWidget) {
    return oldWidget.desktopWorkbench != desktopWorkbench;
  }
}
