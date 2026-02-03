import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class SlTypingIndicator extends StatefulWidget {
  const SlTypingIndicator({
    super.key,
    this.color,
    this.dotCount = 3,
    this.dotSize = 6,
    this.dotSpacing = 5,
    this.duration = const Duration(milliseconds: 900),
  });

  final Color? color;
  final int dotCount;
  final double dotSize;
  final double dotSpacing;
  final Duration duration;

  @override
  State<SlTypingIndicator> createState() => _SlTypingIndicatorState();
}

class _SlTypingIndicatorState extends State<SlTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration)..repeat();

  @override
  void didUpdateWidget(covariant SlTypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      if (_controller.isAnimating) {
        _controller
          ..reset()
          ..repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? DefaultTextStyle.of(context).style.color;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return _StaticDots(
        color: color ?? const Color(0xFF9CA3AF),
        dotCount: widget.dotCount,
        dotSize: widget.dotSize,
        dotSpacing: widget.dotSpacing,
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.dotCount; i++) ...[
              if (i > 0) SizedBox(width: widget.dotSpacing),
              _Dot(
                color: color ?? const Color(0xFF9CA3AF),
                size: widget.dotSize,
                phase: _dotPhase(t, i, widget.dotCount),
              ),
            ],
          ],
        );
      },
    );
  }
}

double _dotPhase(double t, int index, int dotCount) {
  if (dotCount <= 1) return t;
  return (t + (index / dotCount)) % 1.0;
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.color,
    required this.size,
    required this.phase,
  });

  final Color color;
  final double size;
  final double phase;

  double _pulse(double x) {
    // Smooth triangle-ish pulse in [0..1].
    // x: [0..1)
    final shifted = (x - 0.5).abs() * 2; // 0 at center, 1 at edges
    final tri = (1 - shifted).clamp(0.0, 1.0);
    // Ease for a softer feel.
    return math.sin(tri * math.pi * 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final p = _pulse(phase);
    final scale = 0.7 + (0.35 * p);
    final opacity = 0.35 + (0.65 * p);

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: SizedBox(width: size, height: size),
        ),
      ),
    );
  }
}

class _StaticDots extends StatelessWidget {
  const _StaticDots({
    required this.color,
    required this.dotCount,
    required this.dotSize,
    required this.dotSpacing,
  });

  final Color color;
  final int dotCount;
  final double dotSize;
  final double dotSpacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < dotCount; i++) ...[
          if (i > 0) SizedBox(width: dotSpacing),
          Opacity(
            opacity: 0.6,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: SizedBox(width: dotSize, height: dotSize),
            ),
          ),
        ],
      ],
    );
  }
}
