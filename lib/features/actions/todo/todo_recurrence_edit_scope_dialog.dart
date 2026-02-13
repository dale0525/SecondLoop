import 'package:flutter/material.dart';

import '../../../core/backend/app_backend.dart';
import '../../../i18n/strings.g.dart';

Future<TodoRecurrenceEditScope?> showTodoRecurrenceEditScopeDialog(
  BuildContext context,
) {
  final t = context.t.actions.todoRecurrenceEditScope;
  return showDialog<TodoRecurrenceEditScope>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(t.title),
        content: Text(t.message),
        actions: [
          TextButton(
            key: const ValueKey('todo_recurrence_scope_cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t.common.actions.cancel),
          ),
          TextButton(
            key: const ValueKey('todo_recurrence_scope_this_only'),
            onPressed: () =>
                Navigator.of(context).pop(TodoRecurrenceEditScope.thisOnly),
            child: Text(t.thisOnly),
          ),
          TextButton(
            key: const ValueKey('todo_recurrence_scope_this_and_future'),
            onPressed: () => Navigator.of(context)
                .pop(TodoRecurrenceEditScope.thisAndFuture),
            child: Text(t.thisAndFuture),
          ),
          FilledButton(
            key: const ValueKey('todo_recurrence_scope_whole_series'),
            onPressed: () =>
                Navigator.of(context).pop(TodoRecurrenceEditScope.wholeSeries),
            child: Text(t.wholeSeries),
          ),
        ],
      );
    },
  );
}
