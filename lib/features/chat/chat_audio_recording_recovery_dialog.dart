import 'package:flutter/material.dart';

enum AudioRecordingRecoveryDialogAction {
  recover,
  discard,
}

class ChatAudioRecordingRecoveryDialog extends StatelessWidget {
  const ChatAudioRecordingRecoveryDialog({
    super.key,
    required this.recoverableSegmentCount,
    required this.isZhLanguage,
  });

  final int recoverableSegmentCount;
  final bool isZhLanguage;

  static Future<AudioRecordingRecoveryDialogAction?> show(
    BuildContext context, {
    required int recoverableSegmentCount,
  }) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final isZhLanguage = languageCode.toLowerCase().startsWith('zh');
    return showDialog<AudioRecordingRecoveryDialogAction>(
      context: context,
      builder: (dialogContext) {
        return ChatAudioRecordingRecoveryDialog(
          recoverableSegmentCount: recoverableSegmentCount,
          isZhLanguage: isZhLanguage,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        isZhLanguage ? '检测到未完成录音' : 'Interrupted recording detected',
      ),
      content: Text(
        isZhLanguage
            ? '检测到上次录音中断，找到 $recoverableSegmentCount 段可恢复音频。你可以恢复并发送，或直接丢弃。'
            : 'An interrupted recording was found ($recoverableSegmentCount segments). You can recover and send it, or discard it.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context)
                .pop(AudioRecordingRecoveryDialogAction.discard);
          },
          child: Text(
            isZhLanguage ? '丢弃' : 'Discard',
          ),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context)
                .pop(AudioRecordingRecoveryDialogAction.recover);
          },
          child: Text(
            isZhLanguage ? '恢复并发送' : 'Recover & Send',
          ),
        ),
      ],
    );
  }
}
