import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/notifications/review_notification_plan.dart';
import 'package:secondloop/core/notifications/review_reminder_notification_scheduler.dart';
import 'package:secondloop/core/notifications/review_reminder_notifications_gate.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/review/review_queue_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  testWidgets('tap notification payload opens review queue page',
      (tester) async {
    final harness = await _pumpGateHarness(tester);

    harness.scheduler.onTap?.call(
      '${FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix}todo:1',
    );

    await tester.pumpAndSettle();

    expect(find.byType(ReviewQueuePage), findsOneWidget);
  });

  testWidgets('ignores unrelated notification payload', (tester) async {
    final harness = await _pumpGateHarness(tester);

    harness.scheduler.onTap?.call('todo:1');

    await tester.pumpAndSettle();

    expect(find.byType(ReviewQueuePage), findsNothing);
  });

  testWidgets('ignores duplicate taps while review queue is open',
      (tester) async {
    final harness = await _pumpGateHarness(tester);

    harness.scheduler.onTap?.call(
      '${FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix}todo:1',
    );
    harness.scheduler.onTap?.call(
      '${FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix}todo:2',
    );

    await tester.pumpAndSettle();

    expect(
      find.byType(ReviewQueuePage, skipOffstage: false),
      findsOneWidget,
    );
  });
}

Future<_GateHarness> _pumpGateHarness(WidgetTester tester) async {
  final scheduler = _FakeScheduler();
  final navigatorKey = GlobalKey<NavigatorState>();

  await tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: AppBackendScope(
          backend: _Backend(),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: ReviewReminderNotificationsGate(
              navigatorKey: navigatorKey,
              schedulerFactory: (onTap) {
                scheduler.onTap = onTap;
                return scheduler;
              },
              child: const Scaffold(body: Text('home')),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 600));

  expect(scheduler.ensureInitializedCalls, greaterThan(0));

  return _GateHarness(scheduler: scheduler);
}

final class _GateHarness {
  const _GateHarness({required this.scheduler});

  final _FakeScheduler scheduler;
}

final class _FakeScheduler implements ReviewReminderNotificationScheduler {
  int ensureInitializedCalls = 0;
  int scheduleCalls = 0;
  int cancelCalls = 0;
  NotificationTapHandler? onTap;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  Future<void> ensureInitialized() async {
    ensureInitializedCalls += 1;
  }

  @override
  Future<void> schedule(ReviewReminderPlan plan) async {
    scheduleCalls += 1;
  }
}

final class _Backend extends TestAppBackend {
  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    return const <Todo>[
      Todo(
        id: 'todo:1',
        title: 'review this',
        status: 'inbox',
        createdAtMs: 1,
        updatedAtMs: 1,
        reviewStage: 0,
        nextReviewAtMs: 60 * 60 * 1000,
      ),
    ];
  }
}
