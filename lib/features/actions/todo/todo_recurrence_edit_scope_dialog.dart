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
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t.common.actions.cancel),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(TodoRecurrenceEditScope.thisOnly),
            child: Text(t.thisOnly),
          ),
          TextButton(
            onPressed: () => Navigator.of(context)
                .pop(TodoRecurrenceEditScope.thisAndFuture),
            child: Text(t.thisAndFuture),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(TodoRecurrenceEditScope.wholeSeries),
            child: Text(t.wholeSeries),
          ),
        ],
      );
    },
  );
}
