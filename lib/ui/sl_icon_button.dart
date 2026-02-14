import 'package:flutter/material.dart';

import 'sl_tokens.dart';

class SlIconButton extends StatelessWidget {
  const SlIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.size = 32,
    this.iconSize = 18,
    this.tooltip,
    this.color,
    this.borderColor,
    this.overlayBaseColor,
    this.canRequestFocus = true,
    this.triggerOnTapDown = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final Color? color;
  final Color? borderColor;
  final Color? overlayBaseColor;
  final bool canRequestFocus;
  final bool triggerOnTapDown;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(tokens.radiusMd);

    final overlayBase = overlayBaseColor ?? colorScheme.primary;
    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.pressed)) {
        return overlayBase.withOpacity(0.18);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return overlayBase.withOpacity(0.12);
      }
      return null;
    });

    final border =
        borderColor ?? tokens.borderSubtle.withOpacity(isDark ? 0.9 : 0.95);
    final iconColor = color ?? colorScheme.onSurfaceVariant;

    final button = Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: triggerOnTapDown ? null : onPressed,
        onTapDown:
            triggerOnTapDown && onPressed != null ? (_) => onPressed!() : null,
        canRequestFocus: canRequestFocus,
        borderRadius: radius,
        overlayColor: overlay,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor,
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }

    return Tooltip(message: tooltip, child: button);
  }
}
