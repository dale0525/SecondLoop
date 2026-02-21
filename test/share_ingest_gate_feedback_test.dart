import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/share/share_ingest.dart';
import 'package:secondloop/features/share/share_ingest_gate.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('ShareIngestGate shows immediate feedback while draining shares',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ShareIngest.enqueueText('from-share-intent');

    final releaseInsert = Completer<void>();
    final backend = _DelayedInsertBackend(releaseInsert);

    await tester.pumpWidget(
      wrapWithI18n(
        MaterialApp(
          home: AppBackendScope(
            backend: backend,
            child: SessionScope(
              sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
              lock: () {},
              child: const ShareIngestGate(child: SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => backend.insertMessageCalls > 0,
      maxTicks: 20,
      step: const Duration(milliseconds: 20),
    );

    expect(find.byKey(const ValueKey('share_ingest_feedback')), findsOneWidget);

    releaseInsert.complete();
    await _pumpUntil(
      tester,
      () => backend.insertCompleted,
      maxTicks: 40,
      step: const Duration(milliseconds: 20),
    );
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxTicks = 60,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (var i = 0; i < maxTicks; i++) {
    if (condition()) {
      return;
    }
    await tester.pump(step);
  }
}

final class _DelayedInsertBackend extends TestAppBackend {
  _DelayedInsertBackend(this._releaseInsert);

  final Completer<void> _releaseInsert;
  int insertMessageCalls = 0;
  bool insertCompleted = false;

  @override
  Future<Message> insertMessage(
    Uint8List key,
    String conversationId, {
    required String role,
    required String content,
  }) async {
    insertMessageCalls += 1;
    await _releaseInsert.future;
    insertCompleted = true;
    return super.insertMessage(
      key,
      conversationId,
      role: role,
      content: content,
    );
  }
}
