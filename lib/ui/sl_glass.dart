import 'dart:ui';

import 'package:flutter/material.dart';

import 'sl_tokens.dart';

class SlGlass extends StatelessWidget {
  const SlGlass({
    required this.child,
    super.key,
    this.borderRadius,
    this.blurSigma = 18,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.padding,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double blurSigma;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final radius = borderRadius ?? BorderRadius.circular(tokens.radiusLg);
    final fill = color ?? tokens.sidebarBackground;
    final border = borderColor ?? tokens.sidebarBorder;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(color: border, width: borderWidth),
          ),
          child: padding == null
              ? child
              : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}
