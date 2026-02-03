import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/ai/semantic_parse_auto_actions_runner.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';

void main() {
  test('Unscheduled semantic-parse todos enter the review queue', () async {
    SharedPreferences.setMockInitialValues({});

    final backend = _Backend();
    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    await store.upsertTodoFromMessage(
      messageId: 'm1',
      title: '修电视机',
      status: 'inbox',
      dueAtMs: null,
    );

    final args = backend.lastUpsertTodo;
    expect(args, isNotNull);
    expect(args!.id, 'todo:m1');
    expect(args.status, 'inbox');
    expect(args.dueAtMs, isNull);
    expect(args.reviewStage, 0);
    expect(args.nextReviewAtMs, isNotNull);
  });

  test('Scheduled semantic-parse todos do not enter the review queue',
      () async {
    SharedPreferences.setMockInitialValues({});

    final backend = _Backend();
    final store = BackendSemanticParseAutoActionsStore(
      backend: backend,
      sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
    );

    await store.upsertTodoFromMessage(
      messageId: 'm2',
      title: '预约师傅修电视机',
      status: 'inbox',
      dueAtMs: 1,
    );

    final args = backend.lastUpsertTodo;
    expect(args, isNotNull);
    expect(args!.id, 'todo:m2');
    expect(args.status, 'open');
    expect(args.dueAtMs, 1);
    expect(args.reviewStage, isNull);
    expect(args.nextReviewAtMs, isNull);
  });
}

final class _Backend extends TestAppBackend {
  _UpsertTodoArgs? lastUpsertTodo;

  @override
  Future<Todo> upsertTodo(
    Uint8List key, {
    required String id,
    required String title,
    int? dueAtMs,
    required String status,
    String? sourceEntryId,
    int? reviewStage,
    int? nextReviewAtMs,
    int? lastReviewAtMs,
  }) async {
    lastUpsertTodo = _UpsertTodoArgs(
      id: id,
      title: title,
      dueAtMs: dueAtMs,
      status: status,
      sourceEntryId: sourceEntryId,
      reviewStage: reviewStage,
      nextReviewAtMs: nextReviewAtMs,
      lastReviewAtMs: lastReviewAtMs,
    );

    return Todo(
      id: id,
      title: title,
      dueAtMs: dueAtMs == null ? null : PlatformInt64Util.from(dueAtMs),
      status: status,
      sourceEntryId: sourceEntryId,
      createdAtMs: PlatformInt64Util.from(0),
      updatedAtMs: PlatformInt64Util.from(0),
      reviewStage:
          reviewStage == null ? null : PlatformInt64Util.from(reviewStage),
      nextReviewAtMs: nextReviewAtMs == null
          ? null
          : PlatformInt64Util.from(nextReviewAtMs),
      lastReviewAtMs: lastReviewAtMs == null
          ? null
          : PlatformInt64Util.from(lastReviewAtMs),
    );
  }
}

final class _UpsertTodoArgs {
  const _UpsertTodoArgs({
    required this.id,
    required this.title,
    required this.dueAtMs,
    required this.status,
    required this.sourceEntryId,
    required this.reviewStage,
    required this.nextReviewAtMs,
    required this.lastReviewAtMs,
  });

  final String id;
  final String title;
  final int? dueAtMs;
  final String status;
  final String? sourceEntryId;
  final int? reviewStage;
  final int? nextReviewAtMs;
  final int? lastReviewAtMs;
}
