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
}
