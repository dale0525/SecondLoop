import 'package:flutter/material.dart';

import 'sl_tokens.dart';

class SlSurface extends StatelessWidget {
  const SlSurface({
    required this.child,
    super.key,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.borderRadius,
    this.margin,
    this.padding,
  });

  final Widget child;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final radius = borderRadius ?? BorderRadius.circular(tokens.radiusLg);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? tokens.surface,
        borderRadius: radius,
        border: Border.all(
          color: borderColor ?? tokens.borderSubtle,
          width: borderWidth,
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

class SlPageSurface extends StatelessWidget {
  const SlPageSurface({
    required this.child,
    super.key,
    this.maxWidth = 1120,
    this.margin = const EdgeInsets.all(12),
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SlSurface(
          margin: margin,
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
