import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';

Future<bool> showSlDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  Key? confirmButtonKey,
}) async {
  final t = context.t;
  final confirmed = await _showDeleteConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel ?? t.common.actions.delete,
    confirmButtonKey: confirmButtonKey,
  );
  return confirmed == true;
}

Future<bool?> _showDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Key? confirmButtonKey,
}) {
  final t = context.t;
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.common.actions.cancel),
          ),
          FilledButton(
            key: confirmButtonKey,
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}
