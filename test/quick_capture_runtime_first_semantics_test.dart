import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/quick_capture/quick_capture_controller.dart';
import 'package:secondloop/core/quick_capture/quick_capture_scope.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/quick_capture/quick_capture_overlay.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('quick capture does not enqueue local semantic parse jobs',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    final backend = _QuickCaptureRuntimeFirstBackend();
    final controller = await _pumpQuickCapture(tester, backend);

    controller.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const ValueKey('quick_capture_input')),
      '调研一下当前主流的 llm 模型',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(backend.insertedMessages, ['调研一下当前主流的 llm 模型']);
    expect(backend.calls, isNot(contains('enqueueSemanticParseJob')));
    expect(backend.calls, isNot(contains('upsertTodo')));
  });

  testWidgets('quick capture does not open local reminder suggestion sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'semantic_parse_data_consent_v1': true,
    });
    final backend = _QuickCaptureRuntimeFirstBackend();
    final controller = await _pumpQuickCapture(tester, backend);

    controller.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const ValueKey('quick_capture_input')),
      '今晚 8 点提醒我提交周报。',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(backend.insertedMessages, ['今晚 8 点提醒我提交周报。']);
    expect(backend.calls, isNot(contains('upsertTodo')));
    expect(find.byKey(const ValueKey('capture_todo_suggestion_sheet')),
        findsNothing);
  });
}

Future<QuickCaptureController> _pumpQuickCapture(
  WidgetTester tester,
  AppBackend backend,
) async {
  final controller = QuickCaptureController();
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    wrapWithI18n(
      AppBackendScope(
        backend: backend,
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: QuickCaptureScope(
            controller: controller,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              home: QuickCaptureOverlay(
                navigatorKey: navigatorKey,
                child: const Scaffold(body: SizedBox.shrink()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return controller;
}

final class _QuickCaptureRuntimeFirstBackend extends TestAppBackend {
  final List<String> calls = <String>[];
  final List<String> insertedMessages = <String>[];

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    insertedMessages.add(content);
    return super.insertMessage(
      key,
      conversationId,
      role: role,
      content: content,
    );
  }

  @override
  Future<void> enqueueSemanticParseJob(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    calls.add('enqueueSemanticParseJob');
  }

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
    int? manualImportanceNudgeScore,
    int? manualUrgencyNudgeScore,
  }) async {
    calls.add('upsertTodo');
    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      createdAtMs: 0,
      updatedAtMs: 1,
    );
  }
}
