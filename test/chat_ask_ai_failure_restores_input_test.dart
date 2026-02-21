import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

const _kAskAiErrorPrefix = '\u001eSL_ERROR\u001e';

void main() {
  testWidgets('Ask AI failure keeps question bubble and shows retry marker',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final backend = _FailingAskBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'chat_home',
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

    const question = 'hello?';
    await tester.enterText(find.byKey(const ValueKey('chat_input')), question);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_message_row_pending_failed_user')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsNothing);
    expect(
      find.byKey(const ValueKey('chat_ask_ai_retry_pending_user')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat_ask_ai_error_pending_user')),
      findsOneWidget,
    );
    expect(find.textContaining('HTTP 500'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_message_row_pending_failed_user')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsNothing);
    expect(
      find.byKey(const ValueKey('chat_ask_ai_retry_pending_user')),
      findsOneWidget,
    );

    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('chat_input')));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets(
      'Ask AI empty stream is treated as failure and keeps retry marker',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final backend = TestAppBackend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'chat_home',
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

    const question = 'hello?';
    await tester.enterText(find.byKey(const ValueKey('chat_input')), question);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_message_row_pending_failed_user')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsNothing);
    expect(
      find.byKey(const ValueKey('chat_ask_ai_retry_pending_user')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat_ask_ai_error_pending_user')),
      findsOneWidget,
    );
    expect(find.textContaining('Ask AI failed'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.byKey(const ValueKey('chat_message_row_pending_failed_user')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_pending_assistant')),
        findsNothing);
    expect(
      find.byKey(const ValueKey('chat_ask_ai_retry_pending_user')),
      findsOneWidget,
    );

    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('chat_input')));
    expect(field.controller?.text, isEmpty);
  });

  testWidgets(
      'Retry marker re-asks failed question and appends retry result as newest messages',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final backend = _RetryableAskBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: key,
              lock: () {},
              child: const ChatPage(
                conversation: Conversation(
                  id: 'retry_thread',
                  title: 'Retry Thread',
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

    const failedQuestion = 'failed question';
    await tester.enterText(
        find.byKey(const ValueKey('chat_input')), failedQuestion);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('chat_ask_ai_retry_pending_user')),
      findsOneWidget,
    );

    await tester.enterText(
        find.byKey(const ValueKey('chat_input')), 'newer message');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat_message_row_m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_pending_failed_user')),
        findsOneWidget);

    final failedBeforeRetryDy = tester
        .getTopLeft(
            find.byKey(const ValueKey('chat_message_row_pending_failed_user')))
        .dy;
    final newerBeforeRetryDy =
        tester.getTopLeft(find.byKey(const ValueKey('chat_message_row_m1'))).dy;
    expect(newerBeforeRetryDy, greaterThan(failedBeforeRetryDy));

    await tester
        .tap(find.byKey(const ValueKey('chat_ask_ai_retry_pending_user')));
    await tester.pumpAndSettle();

    expect(backend.askCalls, 2);
    expect(find.byKey(const ValueKey('chat_message_row_pending_failed_user')),
        findsNothing);
    expect(find.byKey(const ValueKey('chat_message_row_m2')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat_message_row_m3')), findsOneWidget);

    final newerDy =
        tester.getTopLeft(find.byKey(const ValueKey('chat_message_row_m1'))).dy;
    final retryQuestionDy =
        tester.getTopLeft(find.byKey(const ValueKey('chat_message_row_m2'))).dy;
    final retryAnswerDy =
        tester.getTopLeft(find.byKey(const ValueKey('chat_message_row_m3'))).dy;

    expect(retryQuestionDy, greaterThan(newerDy));
    expect(retryAnswerDy, greaterThan(retryQuestionDy));
  });

  testWidgets(
      'Failed ask bubble can be deleted from desktop hover delete button',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final backend = _TrackingFailingAskBackend();

    try {
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'chat_home',
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

      await tester.enterText(
          find.byKey(const ValueKey('chat_input')), 'hello?');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();

      final failedRow =
          find.byKey(const ValueKey('chat_message_row_pending_failed_user'));
      expect(failedRow, findsOneWidget);

      expect(find.byKey(const ValueKey('message_delete_pending_failed_user')),
          findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(failedRow));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message_delete_pending_failed_user')),
          findsOneWidget);

      await tester.tap(
          find.byKey(const ValueKey('message_delete_pending_failed_user')));
      await tester.pumpAndSettle();
      await _confirmChatMessageDelete(tester);

      expect(
        find.byKey(const ValueKey('chat_message_row_pending_failed_user')),
        findsNothing,
      );
      expect(backend.deleteCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets('Failed ask bubble long-press menu only shows delete',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final backend = _TrackingFailingAskBackend();

    try {
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'chat_home',
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

      await tester.enterText(
          find.byKey(const ValueKey('chat_input')), 'hello?');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();

      final failedRow =
          find.byKey(const ValueKey('chat_message_row_pending_failed_user'));
      expect(failedRow, findsOneWidget);
      final failedText = find.descendant(
        of: failedRow,
        matching: find.text('hello?'),
      );
      expect(failedText, findsOneWidget);

      await tester.longPress(failedText);
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('message_actions_sheet')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('message_action_delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_action_copy')), findsNothing);
      expect(find.byKey(const ValueKey('message_action_edit')), findsNothing);
      expect(
          find.byKey(const ValueKey('message_action_link_todo')), findsNothing);
      expect(
        find.byKey(const ValueKey('message_action_convert_todo')),
        findsNothing,
      );
      expect(
          find.byKey(const ValueKey('message_action_open_todo')), findsNothing);
      expect(
        find.byKey(const ValueKey('message_action_convert_to_info')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('message_action_delete')));
      await tester.pumpAndSettle();
      await _confirmChatMessageDelete(tester);

      expect(
        find.byKey(const ValueKey('chat_message_row_pending_failed_user')),
        findsNothing,
      );
      expect(backend.deleteCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });

  testWidgets('Failed ask bubble right-click menu only shows delete',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final originalPlatformOverride = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final backend = _TrackingFailingAskBackend();

    try {
      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: backend,
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'chat_home',
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

      await tester.enterText(
          find.byKey(const ValueKey('chat_input')), 'hello?');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();

      final failedRow =
          find.byKey(const ValueKey('chat_message_row_pending_failed_user'));
      expect(failedRow, findsOneWidget);

      final failedText = find.descendant(
        of: failedRow,
        matching: find.text('hello?'),
      );
      expect(failedText, findsOneWidget);

      final pos = tester.getCenter(failedText);
      final gesture = await tester.startGesture(
        pos,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('message_context_delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('message_context_copy')), findsNothing);
      expect(
        find.byKey(const ValueKey('message_context_edit')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('message_context_convert_todo')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('message_context_open_todo')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('message_context_convert_to_info')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('message_context_link_todo')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('message_context_delete')));
      await tester.pumpAndSettle();
      await _confirmChatMessageDelete(tester);

      expect(
        find.byKey(const ValueKey('chat_message_row_pending_failed_user')),
        findsNothing,
      );
      expect(backend.deleteCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatformOverride;
    }
  });
}

Future<void> _confirmChatMessageDelete(WidgetTester tester) async {
  expect(find.byType(AlertDialog), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('chat_delete_message_confirm')));
  await tester.pumpAndSettle();
}

final class _FailingAskBackend extends TestAppBackend {
  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) {
    return Stream<String>.fromFuture(
      Future<String>.delayed(
        const Duration(milliseconds: 10),
        () => '${_kAskAiErrorPrefix}HTTP 500',
      ),
    );
  }
}

final class _RetryableAskBackend extends TestAppBackend {
  int askCalls = 0;

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) async* {
    askCalls += 1;
    if (askCalls == 1) {
      yield '${_kAskAiErrorPrefix}HTTP 500';
      return;
    }

    await insertMessage(
      key,
      conversationId,
      role: 'user',
      content: question,
    );
    await insertMessage(
      key,
      conversationId,
      role: 'assistant',
      content: 'retry answer',
    );
    yield 'retry answer';
  }
}

final class _TrackingFailingAskBackend extends _FailingAskBackend {
  int deleteCalls = 0;

  @override
  Future<void> setMessageDeleted(
    Uint8List key,
    String messageId,
    bool isDeleted,
  ) async {
    deleteCalls += 1;
    await super.setMessageDeleted(key, messageId, isDeleted);
  }
}
