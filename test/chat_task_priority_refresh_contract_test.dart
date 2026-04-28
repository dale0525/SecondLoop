import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generic chat refresh makes task priority refresh opt-in', () {
    final source =
        File('lib/features/chat/chat_page_methods_b.dart').readAsStringSync();

    expect(
        source, contains('void _refresh({bool refreshTaskPriority = false})'));
    expect(source, contains('if (!refreshTaskPriority) return;'));
    expect(source, contains('_taskPriorityStore?.markDirty();'));
    expect(
      source,
      contains('_taskPriorityStore?.refresh(force: true)'),
    );
  });

  test('chat sync listener does not refresh task priority directly', () {
    final source =
        File('lib/features/chat/chat_page_methods_a.dart').readAsStringSync();

    expect(source, isNot(contains('_taskPriorityStore?.markDirty();')));
    expect(
      source,
      isNot(contains('_taskPriorityStore?.refresh(force: true)')),
    );
  });
}
