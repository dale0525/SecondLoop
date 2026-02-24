import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';

enum AudioRecordingRecoveryDialogAction {
  recover,
  discard,
}

class ChatAudioRecordingRecoveryDialog extends StatelessWidget {
  const ChatAudioRecordingRecoveryDialog({
    super.key,
    required this.recoverableSegmentCount,
  });

  final int recoverableSegmentCount;

  static Future<AudioRecordingRecoveryDialogAction?> show(
    BuildContext context, {
    required int recoverableSegmentCount,
  }) {
    return showDialog<AudioRecordingRecoveryDialogAction>(
      context: context,
      builder: (dialogContext) {
        return ChatAudioRecordingRecoveryDialog(
          recoverableSegmentCount: recoverableSegmentCount,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogT = context.t.chat.recordingRecoveryDialog;
    return AlertDialog(
      title: Text(
        dialogT.title,
      ),
      content: Text(
        dialogT.description(segmentCount: recoverableSegmentCount),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context)
                .pop(AudioRecordingRecoveryDialogAction.discard);
          },
          child: Text(
            dialogT.actions.discard,
          ),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context)
                .pop(AudioRecordingRecoveryDialogAction.recover);
          },
          child: Text(
            dialogT.actions.recoverAndSend,
          ),
        ),
      ],
    );
  }
}
