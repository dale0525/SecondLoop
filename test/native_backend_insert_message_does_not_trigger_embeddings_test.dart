import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/src/rust/db.dart';

void main() {
  test('NativeAppBackend.insertMessage does not trigger embeddings', () async {
    var insertCalls = 0;
    var processCalls = 0;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop_test',
      dbInsertMessage: ({
        required String appDir,
        required List<int> key,
        required String conversationId,
        required String role,
        required String content,
      }) async {
        insertCalls++;
        return Message(
          id: 'm1',
          conversationId: conversationId,
          role: role,
          content: content,
          createdAtMs: 0,
        );
      },
      dbProcessPendingMessageEmbeddings: ({
        required String appDir,
        required List<int> key,
        required int limit,
      }) async {
        processCalls++;
        return 0;
      },
    );

    final key = Uint8List.fromList(List<int>.filled(32, 1));
    final message = await backend.insertMessage(
      key,
      'c1',
      role: 'user',
      content: 'hello',
    );

    expect(insertCalls, 1);
    expect(processCalls, 0);
    expect(message.content, 'hello');
  });
}
