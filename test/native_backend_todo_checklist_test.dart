import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('NativeAppBackend checklist methods forward args', () async {
    String? capturedAppDirForCreate;
    String? capturedTodoIdForCreate;
    String? capturedContentForCreate;
    String? capturedTodoIdForList;
    String? capturedItemIdForDone;
    bool? capturedDoneValue;
    var progressCalls = 0;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      rustLibInit: () async {},
      dbCreateTodoChecklistItem: ({
        required String appDir,
        required List<int> key,
        required String todoId,
        required String content,
      }) async {
        capturedAppDirForCreate = appDir;
        capturedTodoIdForCreate = todoId;
        capturedContentForCreate = content;
        return TodoChecklistItem(
          id: 'item_1',
          todoId: todoId,
          content: content,
          isDone: false,
          sortOrder: 0,
          createdAtMs: 1,
          updatedAtMs: 1,
        );
      },
      dbListTodoChecklistItems: ({
        required String appDir,
        required List<int> key,
        required String todoId,
      }) async {
        capturedTodoIdForList = todoId;
        return <TodoChecklistItem>[
          TodoChecklistItem(
            id: 'item_1',
            todoId: todoId,
            content: 'Draft launch post',
            isDone: false,
            sortOrder: 0,
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
        ];
      },
      dbSetTodoChecklistItemDone: ({
        required String appDir,
        required List<int> key,
        required String itemId,
        required bool isDone,
      }) async {
        capturedItemIdForDone = itemId;
        capturedDoneValue = isDone;
        return TodoChecklistItem(
          id: itemId,
          todoId: 'todo_1',
          content: 'Draft launch post',
          isDone: isDone,
          sortOrder: 0,
          createdAtMs: 1,
          updatedAtMs: 2,
        );
      },
      dbListTodoChecklistProgress: ({
        required String appDir,
        required List<int> key,
      }) async {
        progressCalls += 1;
        return const <TodoChecklistProgress>[
          TodoChecklistProgress(todoId: 'todo_1', doneCount: 1, totalCount: 2),
        ];
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 7));

    final created = await backend.createTodoChecklistItem(
      key,
      todoId: 'todo_1',
      content: 'Draft launch post',
    );
    final listed = await backend.listTodoChecklistItems(key, 'todo_1');
    final done = await backend.setTodoChecklistItemDone(
      key,
      itemId: 'item_1',
      isDone: true,
    );
    final progress = await backend.listTodoChecklistProgress(key);

    expect(capturedAppDirForCreate, '/tmp/secondloop_test');
    expect(capturedTodoIdForCreate, 'todo_1');
    expect(capturedContentForCreate, 'Draft launch post');
    expect(capturedTodoIdForList, 'todo_1');
    expect(capturedItemIdForDone, 'item_1');
    expect(capturedDoneValue, isTrue);
    expect(progressCalls, 1);

    expect(created.id, 'item_1');
    expect(listed.single.todoId, 'todo_1');
    expect(done.isDone, isTrue);
    expect(progress.single.totalCount, 2);
  });
}
