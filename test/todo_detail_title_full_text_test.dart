import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/todo/todo_detail_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('TodoDetailPage shows full title text', (tester) async {
    const longTitle =
        'This is a very long todo title that should be fully visible in the detail header without ellipsis';

    final backend = _Backend();

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: InkRipple.splashFactory,
          ),
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const TodoDetailPage(
                initialTodo: Todo(
                  id: 't1',
                  title: longTitle,
                  status: 'open',
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

    final titleFinder = find.byKey(const ValueKey('todo_detail_title'));
    expect(titleFinder, findsOneWidget);

    final titleWidget = tester.widget<SelectableText>(titleFinder);
    expect(titleWidget.data, longTitle);
    expect(titleWidget.maxLines, isNull);
  });
}

final class _Backend extends TestAppBackend {
  @override
  Future<List<TodoActivity>> listTodoActivities(
    Uint8List key,
    String todoId,
  ) async =>
      const <TodoActivity>[];

  @override
  Future<List<Attachment>> listTodoActivityAttachments(
    Uint8List key,
    String activityId,
  ) async =>
      const <Attachment>[];
}
