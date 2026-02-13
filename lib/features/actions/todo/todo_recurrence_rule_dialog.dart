import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import 'todo_recurrence_rule.dart';

Future<TodoRecurrenceRule?> showTodoRecurrenceRuleDialog(
  BuildContext context, {
  required TodoRecurrenceRule initialRule,
}) {
  final t = context.t.actions.todoRecurrenceRule;
  var selectedFrequency = initialRule.frequency;
  var selectedInterval = initialRule.interval.clamp(1, 30).toInt();

  String frequencyLabel(TodoRecurrenceFrequency frequency) {
    return switch (frequency) {
      TodoRecurrenceFrequency.daily => t.daily,
      TodoRecurrenceFrequency.weekly => t.weekly,
      TodoRecurrenceFrequency.monthly => t.monthly,
      TodoRecurrenceFrequency.yearly => t.yearly,
    };
  }

  return showDialog<TodoRecurrenceRule>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            key: const ValueKey('todo_recurrence_rule_dialog'),
            title: Text(t.title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<TodoRecurrenceFrequency>(
                    key: const ValueKey('todo_recurrence_rule_frequency_field'),
                    value: selectedFrequency,
                    decoration: InputDecoration(labelText: t.frequencyLabel),
                    items: [
                      for (final frequency in TodoRecurrenceFrequency.values)
                        DropdownMenuItem<TodoRecurrenceFrequency>(
                          value: frequency,
                          child: Text(
                            frequencyLabel(frequency),
                            key: ValueKey(
                              'todo_recurrence_rule_frequency_${frequency.wireValue}',
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedFrequency = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('todo_recurrence_rule_interval_field'),
                    value: selectedInterval,
                    decoration: InputDecoration(labelText: t.intervalLabel),
                    items: [
                      for (var i = 1; i <= 30; i += 1)
                        DropdownMenuItem<int>(
                          value: i,
                          child: Text(
                            i.toString(),
                            key: ValueKey('todo_recurrence_rule_interval_$i'),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selectedInterval = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('todo_recurrence_rule_cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t.common.actions.cancel),
              ),
              FilledButton(
                key: const ValueKey('todo_recurrence_rule_save'),
                onPressed: () {
                  Navigator.of(context).pop(
                    TodoRecurrenceRule(
                      frequency: selectedFrequency,
                      interval: selectedInterval,
                    ),
                  );
                },
                child: Text(context.t.common.actions.save),
              ),
            ],
          );
        },
      );
    },
  );
}
