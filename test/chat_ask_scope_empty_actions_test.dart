import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/ask_scope_empty.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('expand time window action retries without time window',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final backend = _AskScopeActionBackend();

    await _pumpChatPage(tester, backend: backend);
    await _askWithQuestion(tester, 'Generate weekly report');

    expect(backend.invocations, hasLength(1));
    expect(backend.invocations.first.routeKind, 'time_window');

    await tester.tap(
      find.byKey(const ValueKey('ask_scope_empty_action_expandTimeWindow')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(backend.invocations, hasLength(2));
    expect(backend.invocations[1].routeKind, 'default');
  });

  testWidgets('remove include tags action retries with parsed time window',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final backend = _AskScopeActionBackend();

    await _pumpChatPage(tester, backend: backend);
    await _askWithQuestion(tester, 'Generate weekly report');

    expect(backend.invocations, hasLength(1));
    expect(backend.invocations.first.routeKind, 'time_window');

    await tester.tap(
      find.byKey(const ValueKey('ask_scope_empty_action_removeIncludeTags')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(backend.invocations, hasLength(2));
    expect(backend.invocations[1].routeKind, 'time_window');
  });

  testWidgets('switch scope to all action retries with thread scope disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({'ask_ai_data_consent_v1': true});
    final backend = _AskScopeActionBackend();

    await _pumpChatPage(tester, backend: backend);
    await _askWithQuestion(tester, 'Generate weekly report');

    expect(backend.invocations, hasLength(1));
    expect(backend.invocations.first.routeKind, 'time_window');
    expect(backend.invocations.first.thisThreadOnly, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('ask_scope_empty_action_switchScopeToAll')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(backend.invocations, hasLength(2));
    expect(backend.invocations[1].routeKind, 'time_window');
    expect(backend.invocations[1].thisThreadOnly, isFalse);
  });
}

Future<void> _pumpChatPage(
  WidgetTester tester, {
  required AppBackend backend,
}) async {
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
                id: 'main_stream',
                title: 'Main Stream',
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
}

Future<void> _askWithQuestion(WidgetTester tester, String question) async {
  await tester.enterText(find.byKey(const ValueKey('chat_input')), question);
  await tester.pump();

  await tester.tap(find.byKey(const ValueKey('chat_ask_ai')));
  await tester.pump();
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey('ask_scope_empty_card')), findsOneWidget);
  expect(
    find.byKey(const ValueKey('ask_scope_empty_action_expandTimeWindow')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('ask_scope_empty_action_removeIncludeTags')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey('ask_scope_empty_action_switchScopeToAll')),
    findsOneWidget,
  );
}

final class _AskScopeActionBackend extends TestAppBackend {
  final List<_AskInvocation> invocations = <_AskInvocation>[];
  int _replyIndex = 0;

  @override
  Future<List<EmbeddingProfile>> listEmbeddingProfiles(Uint8List key) async =>
      const <EmbeddingProfile>[];

  @override
  Future<String> semanticParseAskAiTimeWindow(
    Uint8List key, {
    required String question,
    required String nowLocalIso,
    required Locale locale,
    required int firstDayOfWeekIndex,
  }) async {
    final now = DateTime.parse(nowLocalIso).toLocal();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return jsonEncode(<String, Object?>{
      'kind': 'both',
      'confidence': 0.95,
      'start_local_iso': start.toIso8601String(),
      'end_local_iso': end.toIso8601String(),
    });
  }

  @override
  Stream<String> askAiStream(
    Uint8List key,
    String conversationId, {
    required String question,
    int topK = 10,
    bool thisThreadOnly = false,
  }) {
    invocations.add(
      _AskInvocation(routeKind: 'default', thisThreadOnly: thisThreadOnly),
    );
    return _nextAnswerStream();
  }

  @override
  Stream<String> askAiStreamTimeWindow(
    Uint8List key,
    String conversationId, {
    required String question,
    required int timeStartMs,
    required int timeEndMs,
    int topK = 10,
    bool thisThreadOnly = false,
  }) {
    invocations.add(
      _AskInvocation(routeKind: 'time_window', thisThreadOnly: thisThreadOnly),
    );
    return _nextAnswerStream();
  }

  Stream<String> _nextAnswerStream() {
    final value = _replyIndex == 0 ? AskScopeEmptyResponse.english : 'ok';
    _replyIndex += 1;
    return Stream<String>.fromIterable(<String>[value]);
  }
}

final class _AskInvocation {
  const _AskInvocation({
    required this.routeKind,
    required this.thisThreadOnly,
  });

  final String routeKind;
  final bool thisThreadOnly;
}
