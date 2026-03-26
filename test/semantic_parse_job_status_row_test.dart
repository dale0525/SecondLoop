import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/chat/semantic_parse_job_status_row.dart';
import 'package:secondloop/features/tags/tag_repository.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  const message = Message(
    id: 'm1',
    conversationId: 'loop_home',
    role: 'user',
    content: '整理周报',
    createdAtMs: 0,
    isMemory: false,
  );

  testWidgets('shows pending tag suggestion row when action is none',
      (WidgetTester tester) async {
    final job = SemanticParseJob(
      messageId: message.id,
      status: 'succeeded',
      attemptId: PlatformInt64Util.from(0),
      attempts: PlatformInt64Util.from(0),
      nextRetryAtMs: null,
      lastError: null,
      appliedActionKind: 'none',
      appliedTodoId: null,
      appliedTodoTitle: null,
      appliedPrevTodoStatus: null,
      suggestedTags: const <String>['work', 'finance'],
      suggestedTagConfidence: 0.72,
      tagSuggestionState: 'pending',
      appliedTagIds: null,
      undoneAtMs: null,
      createdAtMs: PlatformInt64Util.from(0),
      updatedAtMs: PlatformInt64Util.from(0),
    );

    await tester.pumpWidget(_buildHost(message: message, job: job));
    await tester.pump();

    expect(find.textContaining('Suggested tags'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
  });

  testWidgets('shows applied tag row with undo when tags were auto-applied',
      (WidgetTester tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final job = SemanticParseJob(
      messageId: message.id,
      status: 'succeeded',
      attemptId: PlatformInt64Util.from(0),
      attempts: PlatformInt64Util.from(0),
      nextRetryAtMs: null,
      lastError: null,
      appliedActionKind: 'none',
      appliedTodoId: null,
      appliedTodoTitle: null,
      appliedPrevTodoStatus: null,
      suggestedTags: const <String>['work', 'finance'],
      suggestedTagConfidence: 0.82,
      tagSuggestionState: 'applied',
      appliedTagIds: const <String>['tag:work'],
      undoneAtMs: null,
      createdAtMs: PlatformInt64Util.from(nowMs),
      updatedAtMs: PlatformInt64Util.from(nowMs),
    );

    await tester.pumpWidget(_buildHost(message: message, job: job));
    await tester.pump();

    expect(find.textContaining('Added tags'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('dismiss action marks tag suggestion as dismissed',
      (WidgetTester tester) async {
    final backend = _RecordingBackend();
    final job = SemanticParseJob(
      messageId: message.id,
      status: 'succeeded',
      attemptId: PlatformInt64Util.from(0),
      attempts: PlatformInt64Util.from(0),
      nextRetryAtMs: null,
      lastError: null,
      appliedActionKind: 'none',
      appliedTodoId: null,
      appliedTodoTitle: null,
      appliedPrevTodoStatus: null,
      suggestedTags: const <String>['work', 'finance'],
      suggestedTagConfidence: 0.7,
      tagSuggestionState: 'pending',
      appliedTagIds: null,
      undoneAtMs: null,
      createdAtMs: PlatformInt64Util.from(0),
      updatedAtMs: PlatformInt64Util.from(0),
    );

    await tester.pumpWidget(
      _buildHost(
        message: message,
        job: job,
        backend: backend,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Ignore'));
    await tester.pump();

    expect(backend.lastTagSuggestionState, 'dismissed');
    expect(
      backend.lastSuggestedTags,
      equals(const <String>['work', 'finance']),
    );
  });

  testWidgets('shows mobile stay-open reminder while AI is analyzing',
      (WidgetTester tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final job = SemanticParseJob(
        messageId: message.id,
        status: 'pending',
        attemptId: PlatformInt64Util.from(0),
        attempts: PlatformInt64Util.from(0),
        nextRetryAtMs: null,
        lastError: null,
        appliedActionKind: null,
        appliedTodoId: null,
        appliedTodoTitle: null,
        appliedPrevTodoStatus: null,
        suggestedTags: null,
        suggestedTagConfidence: null,
        tagSuggestionState: null,
        appliedTagIds: null,
        undoneAtMs: null,
        createdAtMs: PlatformInt64Util.from(nowMs - 2000),
        updatedAtMs: PlatformInt64Util.from(nowMs - 2000),
      );

      await tester.pumpWidget(_buildHost(message: message, job: job));
      await tester.pump();

      expect(find.text('AI analyzing…'), findsOneWidget);
      expect(
        find.text(
          'Keep the app open while AI analyzes. Leaving may interrupt analysis.',
        ),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('slow pending row shows cancel action and marks job canceled',
      (WidgetTester tester) async {
    final backend = _RecordingBackend();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final job = SemanticParseJob(
      messageId: message.id,
      status: 'pending',
      attemptId: PlatformInt64Util.from(0),
      attempts: PlatformInt64Util.from(0),
      nextRetryAtMs: null,
      lastError: null,
      appliedActionKind: null,
      appliedTodoId: null,
      appliedTodoTitle: null,
      appliedPrevTodoStatus: null,
      suggestedTags: null,
      suggestedTagConfidence: null,
      tagSuggestionState: null,
      appliedTagIds: null,
      undoneAtMs: null,
      createdAtMs: PlatformInt64Util.from(nowMs - 5000),
      updatedAtMs: PlatformInt64Util.from(nowMs - 5000),
    );

    await tester.pumpWidget(
      _buildHost(
        message: message,
        job: job,
        backend: backend,
      ),
    );
    await tester.pump();

    expect(
      find.text('AI is taking longer. Continuing in background…'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(backend.lastCanceledMessageId, 'm1');
  });

  testWidgets('canceled status row stays hidden', (WidgetTester tester) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final job = SemanticParseJob(
      messageId: message.id,
      status: 'canceled',
      attemptId: PlatformInt64Util.from(0),
      attempts: PlatformInt64Util.from(0),
      nextRetryAtMs: null,
      lastError: null,
      appliedActionKind: null,
      appliedTodoId: null,
      appliedTodoTitle: null,
      appliedPrevTodoStatus: null,
      suggestedTags: null,
      suggestedTagConfidence: null,
      tagSuggestionState: null,
      appliedTagIds: null,
      undoneAtMs: null,
      createdAtMs: PlatformInt64Util.from(nowMs - 2000),
      updatedAtMs: PlatformInt64Util.from(nowMs - 2000),
    );

    await tester.pumpWidget(_buildHost(message: message, job: job));
    await tester.pump();

    expect(find.text('AI analysis canceled'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });
}

Widget _buildHost({
  required Message message,
  required SemanticParseJob job,
  AppBackend? backend,
  TagRepository tagRepository = const TagRepository(),
}) {
  return wrapWithI18n(
    MaterialApp(
      home: AppBackendScope(
        backend: backend ?? TestAppBackend(),
        child: SessionScope(
          sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
          lock: () {},
          child: Scaffold(
            body: SemanticParseJobStatusRow(
              message: message,
              job: job,
              tagRepository: tagRepository,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _RecordingBackend extends TestAppBackend {
  String? lastTagSuggestionState;
  List<String>? lastSuggestedTags;
  String? lastCanceledMessageId;

  @override
  Future<void> markSemanticParseJobCanceled(
    Uint8List key, {
    required String messageId,
    required int nowMs,
  }) async {
    lastCanceledMessageId = messageId;
  }

  @override
  Future<void> markSemanticParseJobSucceeded(
    Uint8List key, {
    required String messageId,
    required String appliedActionKind,
    String? appliedTodoId,
    String? appliedTodoTitle,
    String? appliedPrevTodoStatus,
    List<String>? suggestedTags,
    double? suggestedTagConfidence,
    String? tagSuggestionState,
    List<String>? appliedTagIds,
    required int nowMs,
  }) async {
    lastTagSuggestionState = tagSuggestionState;
    lastSuggestedTags = suggestedTags;
  }
}
