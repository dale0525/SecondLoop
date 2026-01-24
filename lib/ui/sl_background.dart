import 'package:flutter/material.dart';

import 'sl_tokens.dart';

class SlBackground extends StatelessWidget {
  const SlBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(color: tokens.background),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isDark) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.75, -0.85),
                  radius: 1.15,
                  colors: [
                    scheme.primary.withOpacity(0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, 0.9),
                  radius: 1.25,
                  colors: [
                    scheme.secondary.withOpacity(0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.02),
                    Colors.transparent,
                    Colors.black.withOpacity(0.04),
                  ],
                ),
              ),
            ),
          ] else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    tokens.background,
                  ],
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
