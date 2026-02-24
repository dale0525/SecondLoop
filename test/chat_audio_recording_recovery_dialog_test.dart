import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_audio_recording_recovery_dialog.dart';

void main() {
  group('ChatAudioRecordingRecoveryDialog', () {
    testWidgets('renders zh content and actions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatAudioRecordingRecoveryDialog(
              recoverableSegmentCount: 3,
              isZhLanguage: true,
            ),
          ),
        ),
      );

      expect(find.text('检测到未完成录音'), findsOneWidget);
      expect(find.textContaining('找到 3 段可恢复音频'), findsOneWidget);
      expect(find.text('丢弃'), findsOneWidget);
      expect(find.text('恢复并发送'), findsOneWidget);
    });

    testWidgets('renders en content and actions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatAudioRecordingRecoveryDialog(
              recoverableSegmentCount: 2,
              isZhLanguage: false,
            ),
          ),
        ),
      );

      expect(find.text('Interrupted recording detected'), findsOneWidget);
      expect(
        find.textContaining('An interrupted recording was found (2 segments).'),
        findsOneWidget,
      );
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Recover & Send'), findsOneWidget);
    });

    testWidgets('show resolves locale and returns action', (tester) async {
      Future<AudioRecordingRecoveryDialogAction?>? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const <Locale>[
            Locale('en'),
            Locale('zh', 'CN'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    dialogResult = ChatAudioRecordingRecoveryDialog.show(
                      context,
                      recoverableSegmentCount: 1,
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('检测到未完成录音'), findsOneWidget);

      await tester.tap(find.text('恢复并发送'));
      await tester.pumpAndSettle();

      expect(
        await dialogResult,
        AudioRecordingRecoveryDialogAction.recover,
      );
    });
  });
}
