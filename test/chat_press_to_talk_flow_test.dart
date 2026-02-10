import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_i18n.dart';
import 'widget_test.dart' show FakeBackend;

void main() {
  testWidgets(
      'Android press-to-talk: release switches to text input and inserts recognized words',
      (tester) async {
    final oldPlatform = debugDefaultTargetPlatformOverride;
    final oldSpeechPlatform = SpeechToTextPlatform.instance;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final fakeSpeechPlatform = _FakeSpeechToTextPlatform(
      recognizedWords: 'buy milk tomorrow',
      resultDelay: const Duration(milliseconds: 350),
      emitListeningStatus: false,
    );
    SpeechToTextPlatform.instance = fakeSpeechPlatform;

    try {
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: FakeBackend(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'c1',
                    title: 'Chat',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chat_toggle_voice_input')));
      await tester.pumpAndSettle();

      final talkButton = find.byKey(const ValueKey('chat_press_to_talk'));
      expect(talkButton, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(talkButton));
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        find.byKey(const ValueKey('chat_press_to_talk_overlay_recording')),
        findsOneWidget,
      );

      await gesture.up();
      await tester.pump();

      expect(find.byKey(const ValueKey('chat_input')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat_press_to_talk_overlay_recognizing')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chat_press_to_talk_overlay_recognizing')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('chat_press_to_talk')), findsNothing);

      final input =
          tester.widget<TextField>(find.byKey(const ValueKey('chat_input')));
      expect(input.controller?.text, contains('buy milk tomorrow'));
    } finally {
      SpeechToTextPlatform.instance = oldSpeechPlatform;
      debugDefaultTargetPlatformOverride = oldPlatform;
    }
  });
}

final class _FakeSpeechToTextPlatform extends SpeechToTextPlatform
    with MockPlatformInterfaceMixin {
  _FakeSpeechToTextPlatform({
    this.emitListeningStatus = true,
    required this.recognizedWords,
    this.resultDelay = Duration.zero,
  });

  final bool emitListeningStatus;
  final String recognizedWords;
  final Duration resultDelay;

  bool _listening = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) async {
    return true;
  }

  @override
  Future<bool> listen({
    String? localeId,
    partialResults = true,
    onDevice = false,
    int listenMode = 0,
    sampleRate = 0,
    SpeechListenOptions? options,
  }) async {
    _listening = true;
    if (emitListeningStatus) {
      onStatus?.call('listening');
    }
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_listening) return;
    _listening = false;

    Future<void>.delayed(resultDelay, () {
      final resultJson = jsonEncode({
        'alternates': [
          {
            'recognizedWords': recognizedWords,
            'confidence': 0.92,
          }
        ],
        'finalResult': true,
      });
      onTextRecognition?.call(resultJson);
      onStatus?.call('done');
    });
  }

  @override
  Future<void> cancel() async {
    _listening = false;
    onStatus?.call('notListening');
  }

  @override
  Future<List<dynamic>> locales() async {
    return const <String>[
      'en_US:English (US)',
      'zh_CN:Chinese (CN)',
    ];
  }
}
