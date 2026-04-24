import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import 'sync_switch_direction.dart';

Future<SyncSwitchDirection?> showSyncSwitchDirectionDialog(
  BuildContext dialogContext,
) {
  final labels = dialogContext.t.sync.switchDirection;
  return showDialog<SyncSwitchDirection>(
    context: dialogContext,
    barrierDismissible: false,
    builder: (context) {
      Widget optionButton({
        required String label,
        required SyncSwitchDirection direction,
        bool primary = false,
      }) {
        final child = Text(label, textAlign: TextAlign.center);
        void onPressed() => Navigator.of(context).pop(direction);
        if (primary) {
          return SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onPressed, child: child),
          );
        }
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(onPressed: onPressed, child: child),
        );
      }

      return AlertDialog(
        title: Text(labels.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(labels.message),
            const SizedBox(height: 16),
            optionButton(
              label: labels.localReplacesRemote,
              direction: SyncSwitchDirection.localReplacesRemote,
            ),
            const SizedBox(height: 8),
            optionButton(
              label: labels.remoteReplacesLocal,
              direction: SyncSwitchDirection.remoteReplacesLocal,
            ),
            const SizedBox(height: 8),
            optionButton(
              label: labels.merge,
              direction: SyncSwitchDirection.merge,
              primary: true,
            ),
          ],
        ),
      );
    },
  );
}
