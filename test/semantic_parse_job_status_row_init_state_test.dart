import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/semantic_parse_job_status_row.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets(
    'SemanticParseJobStatusRow does not depend on inherited widgets in initState',
    (WidgetTester tester) async {
      const message = Message(
        id: 'm1',
        conversationId: 'loop_home',
        role: 'user',
        content: 'Hello',
        createdAtMs: 0,
        isMemory: false,
      );
      final job = SemanticParseJob(
        messageId: message.id,
        status: 'succeeded',
        attempts: PlatformInt64Util.from(0),
        nextRetryAtMs: null,
        lastError: null,
        appliedActionKind: 'create',
        appliedTodoId: 't1',
        appliedTodoTitle: 'Todo',
        appliedPrevTodoStatus: null,
        undoneAtMs: null,
        createdAtMs: PlatformInt64Util.from(0),
        updatedAtMs: PlatformInt64Util.from(0),
      );

      await tester.pumpWidget(
        wrapWithI18n(
          MaterialApp(
            home: AppBackendScope(
              backend: TestAppBackend(),
              child: SessionScope(
                sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
                lock: () {},
                child: Scaffold(
                  body: SemanticParseJobStatusRow(message: message, job: job),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}
