import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/core/backend/serialized_rust_handler.dart';

void main() {
  test('SerializedRustHandler schedules Rust calls one at a time', () async {
    final handler = SerializedRustHandler();
    final firstCompleter = Completer<int>();
    final events = <String>[];

    final first = handler.schedule(() async {
      events.add('first:start');
      return firstCompleter.future.whenComplete(() {
        events.add('first:end');
      });
    });

    final second = handler.schedule(() async {
      events.add('second:start');
      return 2;
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['first:start']);

    firstCompleter.complete(1);

    expect(await first, 1);
    expect(await second, 2);
    expect(
      events,
      <String>['first:start', 'first:end', 'second:start'],
    );
  });

  test('SerializedRustHandler continues after a failed Rust call', () async {
    final handler = SerializedRustHandler();
    final events = <String>[];

    final first = handler.schedule(() async {
      events.add('first:start');
      throw StateError('boom');
    });

    final second = handler.schedule(() async {
      events.add('second:start');
      return 2;
    });

    await expectLater(first, throwsA(isA<StateError>()));
    expect(await second, 2);
    expect(events, <String>['first:start', 'second:start']);
  });
}
