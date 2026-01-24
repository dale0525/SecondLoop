import 'package:flutter/material.dart';

import 'sl_tokens.dart';

class SlFocusRing extends StatefulWidget {
  const SlFocusRing({
    required this.child,
    super.key,
    this.borderRadius,
    this.enabled = true,
    this.showOnHover = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final bool enabled;
  final bool showOnHover;

  @override
  State<SlFocusRing> createState() => _SlFocusRingState();
}

class _SlFocusRingState extends State<SlFocusRing> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = SlTokens.of(context);
    final radius =
        widget.borderRadius ?? BorderRadius.circular(tokens.radiusLg);

    final showRing =
        widget.enabled && (_focused || (widget.showOnHover && _hovered));

    final ring = tokens.ring;
    final shadows = showRing
        ? <BoxShadow>[
            BoxShadow(
              color: ring.withOpacity(_focused ? 0.34 : 0.16),
              blurRadius: 18,
              spreadRadius: _focused ? 2 : 1,
              offset: Offset.zero,
            ),
          ]
        : const <BoxShadow>[];

    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        onEnter:
            widget.showOnHover ? (_) => setState(() => _hovered = true) : null,
        onExit:
            widget.showOnHover ? (_) => setState(() => _hovered = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: shadows,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
