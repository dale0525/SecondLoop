import 'package:flutter/material.dart';

import 'sl_tokens.dart';

class SlIconButtonFrame extends StatefulWidget {
  const SlIconButtonFrame({
    required this.icon,
    super.key,
    this.size = 40,
    this.iconSize = 18,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  State<SlIconButtonFrame> createState() => _SlIconButtonFrameState();
}

class _SlIconButtonFrameState extends State<SlIconButtonFrame> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final radius = BorderRadius.circular(tokens.radiusMd);
    final background = _hovered
        ? colorScheme.primary.withOpacity(isDark ? 0.14 : 0.08)
        : Colors.transparent;
    final border = tokens.borderSubtle.withOpacity(isDark ? 0.9 : 0.95);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: Border.all(color: border),
        ),
        child: Icon(
          widget.icon,
          size: widget.iconSize,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
