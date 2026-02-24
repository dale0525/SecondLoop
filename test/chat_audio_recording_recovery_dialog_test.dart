import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/chat/chat_audio_recording_recovery_dialog.dart';
import 'package:secondloop/i18n/strings.g.dart';

import 'test_i18n.dart';

void main() {
  setUp(() {
    LocaleSettings.setLocale(AppLocale.en);
  });

  group('ChatAudioRecordingRecoveryDialog', () {
    testWidgets('renders zh content and actions', (tester) async {
      LocaleSettings.setLocale(AppLocale.zhCn);

      await tester.pumpWidget(
        wrapWithI18n(
          const MaterialApp(
            locale: Locale('zh', 'CN'),
            home: Scaffold(
              body: ChatAudioRecordingRecoveryDialog(
                recoverableSegmentCount: 3,
              ),
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
        wrapWithI18n(
          const MaterialApp(
            locale: Locale('en'),
            home: Scaffold(
              body: ChatAudioRecordingRecoveryDialog(
                recoverableSegmentCount: 2,
              ),
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
      LocaleSettings.setLocale(AppLocale.zhCn);

      Future<AudioRecordingRecoveryDialogAction?>? dialogResult;

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
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
