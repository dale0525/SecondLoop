import 'package:flutter/material.dart';

import '../../../ui/sl_tokens.dart';
import 'task_hub_priority_animation_controller.dart';

class TaskHubPriorityAnimationOverlay extends StatelessWidget {
  const TaskHubPriorityAnimationOverlay({
    required this.animation,
    required this.onCompleted,
    super.key,
  });

  final TaskHubPriorityOverlayState animation;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SlTokens.of(context);
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(
          'task_hub_priority_animation_overlay_${animation.todoId}_${animation.token}',
        ),
        tween: Tween<double>(begin: 0, end: 1),
        duration: animation.totalDuration,
        curve: Curves.linear,
        onEnd: onCompleted,
        builder: (context, progress, _) {
          final flightCurve = Curves.easeOutCubic.transform(progress);
          final rect = Rect.lerp(
            animation.beginRect,
            animation.endRect,
            flightCurve,
          );
          if (rect == null) return const SizedBox.shrink();
          final targetScale = 0.94 + (0.10 * (1 - flightCurve));
          final targetOpacity = 0.18 + (0.20 * flightCurve);
          final shadowOpacity = 0.24 + (0.08 * (1 - flightCurve));
          return Stack(
            children: [
              Positioned.fromRect(
                rect: animation.endRect.inflate(8),
                child: Transform.scale(
                  scale: targetScale,
                  child: DecoratedBox(
                    key: const ValueKey('task_hub_priority_animation_target'),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(tokens.radiusLg + 6),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(
                          targetOpacity,
                        ),
                        width: 2,
                      ),
                      color: theme.colorScheme.primary.withOpacity(
                        targetOpacity * 0.22,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(
                            targetOpacity * 0.45,
                          ),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: rect,
                child: Material(
                  key: const ValueKey('task_hub_priority_animation_overlay'),
                  elevation: 12,
                  color: theme.colorScheme.surface,
                  shadowColor: theme.colorScheme.shadow.withOpacity(
                    shadowOpacity,
                  ),
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(tokens.radiusLg),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.30),
                        width: 1.5,
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          theme.colorScheme.primary.withOpacity(0.10),
                          theme.colorScheme.surface,
                        ],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        animation.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
