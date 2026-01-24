import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_surface.dart';
import 'time/time_resolver.dart';

abstract class CaptureTodoDecision {
  const CaptureTodoDecision();
}

class CaptureTodoScheduleDecision extends CaptureTodoDecision {
  const CaptureTodoScheduleDecision(this.dueAtLocal);

  final DateTime dueAtLocal;
}

class CaptureTodoReviewDecision extends CaptureTodoDecision {
  const CaptureTodoReviewDecision();
}

class CaptureTodoNoThanksDecision extends CaptureTodoDecision {
  const CaptureTodoNoThanksDecision();
}

Future<CaptureTodoDecision?> showCaptureTodoSuggestionSheet(
  BuildContext context, {
  required String title,
  required LocalTimeResolution? timeResolution,
}) {
  return showModalBottomSheet<CaptureTodoDecision>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SlSurface(
            key: const ValueKey('capture_todo_suggestion_sheet'),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.actions.capture.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(title),
                  if (timeResolution != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.t.actions.capture.pickTime,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in timeResolution.candidates)
                          SlButton(
                            onPressed: () => Navigator.of(context).pop(
                              CaptureTodoScheduleDecision(c.dueAtLocal),
                            ),
                            child: Text(c.label),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SlButton(
                      variant: SlButtonVariant.outline,
                      onPressed: () => Navigator.of(context).pop(
                        const CaptureTodoReviewDecision(),
                      ),
                      child: Text(context.t.actions.capture.reviewLater),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    SlButton(
                      onPressed: () => Navigator.of(context).pop(
                        const CaptureTodoReviewDecision(),
                      ),
                      child: Text(context.t.actions.capture.reviewLater),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SlButton(
                    variant: SlButtonVariant.outline,
                    onPressed: () => Navigator.of(context).pop(
                      const CaptureTodoNoThanksDecision(),
                    ),
                    child: Text(context.t.actions.capture.justSave),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
