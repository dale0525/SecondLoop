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
      child: TweenAnimationBuilder<Rect?>(
        key: ValueKey(
          'task_hub_priority_animation_overlay_${animation.todoId}_${animation.token}',
        ),
        tween: RectTween(begin: animation.beginRect, end: animation.endRect),
        duration: animation.duration,
        curve: Curves.easeOutCubic,
        onEnd: onCompleted,
        builder: (context, rect, _) {
          if (rect == null) return const SizedBox.shrink();
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: Material(
                  key: const ValueKey('task_hub_priority_animation_overlay'),
                  elevation: 8,
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(tokens.radiusLg),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(tokens.radiusLg),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.18),
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        animation.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
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
