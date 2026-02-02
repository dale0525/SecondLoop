import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/ai/message_embeddings_index_gate.dart';
import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/backend/native_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';

void main() {
  testWidgets('MessageEmbeddingsIndexGate drains pending message embeddings',
      (tester) async {
    var remaining = 3;
    var calls = 0;

    final backend = NativeAppBackend(
      appDirProvider: () async => '/tmp/secondloop-test',
      dbProcessPendingMessageEmbeddings: ({
        required String appDir,
        required List<int> key,
        required int limit,
      }) async {
        calls += 1;
        if (remaining <= 0) return 0;
        remaining -= 1;
        return 1;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: const MessageEmbeddingsIndexGate(
              child: SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(calls, 0);

    await tester.pump(const Duration(seconds: 6));
    expect(calls, greaterThanOrEqualTo(4));
  });
}
