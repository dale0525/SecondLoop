import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/features/actions/todo/message_auto_actions_queue.dart';

import 'test_backend.dart';

void main() {
  test('MessageAutoActionsQueue runs jobs serially', () async {
    final backend = TestAppBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    final m1 = await backend.insertMessage(
      key,
      'main_stream',
      role: 'user',
      content: 'first',
    );
    final m2 = await backend.insertMessage(
      key,
      'main_stream',
      role: 'user',
      content: 'second',
    );

    final events = <String>[];
    final firstStarted = Completer<void>();
    final unblockFirst = Completer<void>();

    final queue = MessageAutoActionsQueue(
      backend: backend,
      sessionKey: key,
      handler: (message, rawText) async {
        events.add('start:${message.id}');
        if (message.id == m1.id) {
          firstStarted.complete();
          await unblockFirst.future;
        }
        events.add('done:${message.id}');
      },
    );

    queue.enqueue(
      message: m1,
      rawText: 'first',
      createdAtMs: m1.createdAtMs,
    );
    queue.enqueue(
      message: m2,
      rawText: 'second',
      createdAtMs: m2.createdAtMs,
    );

    await firstStarted.future;
    expect(events, <String>['start:${m1.id}']);

    unblockFirst.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>[
      'start:${m1.id}',
      'done:${m1.id}',
      'start:${m2.id}',
      'done:${m2.id}',
    ]);
  });

  test('MessageAutoActionsQueue skips deleted/edited messages', () async {
    final backend = TestAppBackend();
    final key = Uint8List.fromList(List<int>.filled(32, 1));

    final m1 = await backend.insertMessage(
      key,
      'main_stream',
      role: 'user',
      content: 'first',
    );
    final m2 = await backend.insertMessage(
      key,
      'main_stream',
      role: 'user',
      content: 'second',
    );

    final events = <String>[];
    final firstStarted = Completer<void>();
    final unblockFirst = Completer<void>();

    final queue = MessageAutoActionsQueue(
      backend: backend,
      sessionKey: key,
      handler: (message, rawText) async {
        events.add('run:${message.id}');
        if (message.id == m1.id) {
          firstStarted.complete();
          await unblockFirst.future;
        }
      },
    );

    queue.enqueue(
      message: m1,
      rawText: 'first',
      createdAtMs: m1.createdAtMs,
    );
    queue.enqueue(
      message: m2,
      rawText: 'second',
      createdAtMs: m2.createdAtMs,
    );

    await firstStarted.future;
    await backend.editMessage(key, m2.id, 'second edited');

    unblockFirst.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>['run:${m1.id}']);
  });
}
