import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/features/chat/chat_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('Semantic parse enqueues jobs without Ask AI consent',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ask_ai_data_consent_v1': false,
      'semantic_parse_data_consent_v1': true,
    });

    final backend = _Backend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          home: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: AppBackendScope(
              backend: backend,
              child: const ChatPage(
                conversation: Conversation(
                  id: 'loop_home',
                  title: 'Loop',
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

    await tester.enterText(find.byKey(const ValueKey('chat_input')), '修电视机');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat_send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(backend.calls, contains('enqueueSemanticParseJob'));

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    'Semantic parse status query is skipped when semantic consent is disabled',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'ask_ai_data_consent_v1': false,
        'semantic_parse_data_consent_v1': false,
      });

      final backend = _SemanticJobsBackend(
        initialMessages: const <Message>[
          Message(
            id: 'm1',
            conversationId: 'loop_home',
            role: 'user',
            content: '复习英语课堂视频',
            createdAtMs: 1,
            isMemory: true,
          ),
        ],
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            locale: const Locale('zh', 'CN'),
            home: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: AppBackendScope(
                backend: backend,
                child: const ChatPage(
                  conversation: Conversation(
                    id: 'loop_home',
                    title: 'Loop',
                    createdAtMs: 0,
                    updatedAtMs: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('复习英语课堂视频'), findsOneWidget);
      expect(
        backend.calls,
        isNot(contains('listSemanticParseJobsByMessageIds')),
      );
    },
  );
}

final class _Backend extends TestAppBackend {
  final List<String> calls = <String>[];
  final Map<String, SemanticParseJob> _jobsByMessageId =
      <String, SemanticParseJob>{};

  @override
  Future<void> enqueueSemanticParseJob(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    calls.add('enqueueSemanticParseJob');
    final createdAtMs = nowMs - 1000;
    _jobsByMessageId[messageId] = SemanticParseJob(
      messageId: messageId,
      status: 'pending',
      attempts: PlatformInt64Util.from(0),
      nextRetryAtMs: null,
      lastError: null,
      appliedActionKind: null,
      appliedTodoId: null,
      appliedTodoTitle: null,
      appliedPrevTodoStatus: null,
      undoneAtMs: null,
      createdAtMs: PlatformInt64Util.from(createdAtMs),
      updatedAtMs: PlatformInt64Util.from(createdAtMs),
    );
  }

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    calls.add('listSemanticParseJobsByMessageIds');
    final jobs = <SemanticParseJob>[];
    for (final id in messageIds) {
      final job = _jobsByMessageId[id];
      if (job != null) jobs.add(job);
    }
    return jobs;
  }
}

final class _SemanticJobsBackend extends TestAppBackend {
  _SemanticJobsBackend({required super.initialMessages});

  final List<String> calls = <String>[];

  @override
  Future<List<SemanticParseJob>> listSemanticParseJobsByMessageIds(
    Uint8List key, {
    required List<String> messageIds,
  }) async {
    calls.add('listSemanticParseJobsByMessageIds');
    final createdAtMs = DateTime.now().millisecondsSinceEpoch - 5000;
    return messageIds
        .map(
          (id) => SemanticParseJob(
            messageId: id,
            status: 'pending',
            attempts: PlatformInt64Util.from(0),
            nextRetryAtMs: null,
            lastError: null,
            appliedActionKind: null,
            appliedTodoId: null,
            appliedTodoTitle: null,
            appliedPrevTodoStatus: null,
            undoneAtMs: null,
            createdAtMs: PlatformInt64Util.from(createdAtMs),
            updatedAtMs: PlatformInt64Util.from(createdAtMs),
          ),
        )
        .toList(growable: false);
  }
}
