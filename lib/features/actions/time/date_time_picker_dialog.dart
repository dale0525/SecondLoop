import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../ui/sl_button.dart';
import '../../../ui/sl_surface.dart';

Future<DateTime?> showSlDateTimePickerDialog(
  BuildContext context, {
  required DateTime initialLocal,
  required DateTime firstDate,
  required DateTime lastDate,
  required String title,
  Key? surfaceKey,
}) async {
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      var selectedDate = DateTime(
        initialLocal.year,
        initialLocal.month,
        initialLocal.day,
      );
      var selectedTime = TimeOfDay(
        hour: initialLocal.hour,
        minute: initialLocal.minute,
      );

      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SlSurface(
              key: surfaceKey,
              padding: const EdgeInsets.all(12),
              child: StatefulBuilder(
                builder: (context, setState) {
                  DropdownMenuItem<int> item(int value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.toString().padLeft(2, '0')),
                      );

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        CalendarDatePicker(
                          initialDate: selectedDate,
                          firstDate: firstDate,
                          lastDate: lastDate,
                          onDateChanged: (date) =>
                              setState(() => selectedDate = date),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          MaterialLocalizations.of(context).formatTimeOfDay(
                            selectedTime,
                            alwaysUse24HourFormat:
                                MediaQuery.of(context).alwaysUse24HourFormat,
                          ),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: selectedTime.hour,
                                items: [for (var i = 0; i < 24; i++) item(i)],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(
                                    () => selectedTime = TimeOfDay(
                                      hour: value,
                                      minute: selectedTime.minute,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: selectedTime.minute,
                                items: [for (var i = 0; i < 60; i++) item(i)],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(
                                    () => selectedTime = TimeOfDay(
                                      hour: selectedTime.hour,
                                      minute: value,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SlButton(
                              variant: SlButtonVariant.outline,
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(context.t.common.actions.cancel),
                            ),
                            const SizedBox(width: 8),
                            SlButton(
                              onPressed: () => Navigator.of(context).pop(
                                DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                  selectedTime.hour,
                                  selectedTime.minute,
                                ),
                              ),
                              child: Text(context.t.common.actions.save),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}
