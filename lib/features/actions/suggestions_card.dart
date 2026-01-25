import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../ui/sl_button.dart';
import '../../ui/sl_surface.dart';
import 'settings/actions_settings_store.dart';
import 'time/date_time_picker_dialog.dart';
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
}) async {
  final settings = await ActionsSettingsStore.load();
  if (!context.mounted) return null;

  final nowLocal = DateTime.now();
  final initial = timeResolution?.candidates.firstOrNull?.dueAtLocal ??
      DateTime(
        nowLocal.year,
        nowLocal.month,
        nowLocal.day,
        settings.dayEndTime.hour,
        settings.dayEndTime.minute,
      );

  return showDialog<CaptureTodoDecision>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
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
                      dialogContext.t.actions.capture.title,
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(title),
                    const SizedBox(height: 12),
                    Text(
                      dialogContext.t.actions.capture.pickTime,
                      style: Theme.of(dialogContext).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    if (timeResolution != null) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in timeResolution.candidates)
                            SlButton(
                              onPressed: () => Navigator.of(dialogContext).pop(
                                CaptureTodoScheduleDecision(c.dueAtLocal),
                              ),
                              child: Text(c.label),
                            ),
                        ],
                      ),
                    ] else ...[
                      SlButton(
                        onPressed: null,
                        variant: SlButtonVariant.outline,
                        child:
                            Text(dialogContext.t.actions.calendar.noAutoTime),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SlButton(
                      key: const ValueKey('capture_todo_option_pick_custom'),
                      variant: SlButtonVariant.outline,
                      onPressed: () async {
                        final picked = await showSlDateTimePickerDialog(
                          dialogContext,
                          initialLocal: initial,
                          firstDate: DateTime(nowLocal.year - 1),
                          lastDate: DateTime(nowLocal.year + 3),
                          title: dialogContext.t.actions.calendar.pickCustom,
                          surfaceKey: const ValueKey(
                            'capture_todo_custom_datetime_picker',
                          ),
                        );
                        if (picked == null || !dialogContext.mounted) return;

                        Navigator.of(dialogContext).pop(
                          CaptureTodoScheduleDecision(picked),
                        );
                      },
                      child: Text(dialogContext.t.actions.calendar.pickCustom),
                    ),
                    const SizedBox(height: 12),
                    SlButton(
                      variant: SlButtonVariant.outline,
                      onPressed: () => Navigator.of(dialogContext).pop(
                        const CaptureTodoReviewDecision(),
                      ),
                      child: Text(dialogContext.t.actions.capture.reviewLater),
                    ),
                    const SizedBox(height: 8),
                    SlButton(
                      variant: SlButtonVariant.outline,
                      onPressed: () => Navigator.of(dialogContext).pop(
                        const CaptureTodoNoThanksDecision(),
                      ),
                      child: Text(dialogContext.t.actions.capture.justSave),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

extension on List<DueCandidate> {
  DueCandidate? get firstOrNull => isEmpty ? null : first;
}
