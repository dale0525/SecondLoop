import 'package:flutter/material.dart';

import '../ui/sl_surface.dart';
import '../ui/sl_tokens.dart';

const double _kWideWebAppShellBreakpoint = 720;

class WebAppPanelFrame extends StatelessWidget {
  const WebAppPanelFrame({
    required this.child,
    super.key,
    this.maxWidth = 880,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWideShell =
            constraints.maxWidth >= _kWideWebAppShellBreakpoint;
        return SlPageSurface(
          maxWidth: maxWidth,
          margin: useWideShell
              ? const EdgeInsets.all(24)
              : const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusLg),
            child: child,
          ),
        );
      },
    );
  }
}
