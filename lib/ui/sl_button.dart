import 'package:flutter/material.dart';

import 'sl_tokens.dart';

enum SlButtonVariant {
  primary,
  secondary,
  outline,
}

class SlButton extends StatelessWidget {
  const SlButton({
    required this.onPressed,
    required this.child,
    super.key,
    this.buttonKey,
    this.icon,
    this.variant = SlButtonVariant.primary,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Key? buttonKey;
  final Widget? icon;
  final SlButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(context);
    return switch (variant) {
      SlButtonVariant.primary => icon == null
          ? FilledButton(
              key: buttonKey,
              onPressed: onPressed,
              style: style,
              child: child,
            )
          : FilledButton.icon(
              key: buttonKey,
              onPressed: onPressed,
              style: style,
              icon: icon!,
              label: child,
            ),
      SlButtonVariant.secondary => icon == null
          ? FilledButton.tonal(
              key: buttonKey,
              onPressed: onPressed,
              style: style,
              child: child,
            )
          : FilledButton.tonalIcon(
              key: buttonKey,
              onPressed: onPressed,
              style: style,
              icon: icon!,
              label: child,
            ),
      SlButtonVariant.outline => icon == null
          ? OutlinedButton(
              key: buttonKey,
              onPressed: onPressed,
              style: style,
              child: child,
            )
          : OutlinedButton.icon(
              key: buttonKey,
              onPressed: onPressed,
              style: style,
              icon: icon!,
              label: child,
            ),
    };
  }

  ButtonStyle _styleFor(BuildContext context) {
    final tokens = SlTokens.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    const minHeight = 40.0;
    const minSize = Size(0, minHeight);
    final radius = BorderRadius.circular(tokens.radiusMd);

    final overlay = MaterialStateProperty.resolveWith<Color?>((states) {
      if (states.contains(MaterialState.pressed)) {
        return colorScheme.primary.withOpacity(0.18);
      }
      if (states.contains(MaterialState.hovered) ||
          states.contains(MaterialState.focused)) {
        return colorScheme.primary.withOpacity(0.12);
      }
      return null;
    });

    final side = MaterialStatePropertyAll(
      BorderSide(color: tokens.borderSubtle.withOpacity(0.9)),
    );

    return ButtonStyle(
      minimumSize: const MaterialStatePropertyAll(minSize),
      padding: const MaterialStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      shape: MaterialStatePropertyAll(
        RoundedRectangleBorder(borderRadius: radius),
      ),
      overlayColor: overlay,
      side: variant == SlButtonVariant.outline ? side : null,
    );
  }
}
