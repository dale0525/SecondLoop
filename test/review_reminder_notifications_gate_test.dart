import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:secondloop/core/backend/app_backend.dart';
import 'package:secondloop/core/notifications/review_notification_plan.dart';
import 'package:secondloop/core/notifications/review_reminder_in_app_fallback_prefs.dart';
import 'package:secondloop/core/notifications/review_reminder_notification_scheduler.dart';
import 'package:secondloop/core/notifications/review_reminder_notifications_gate.dart';
import 'package:secondloop/core/session/session_scope.dart';
import 'package:secondloop/features/actions/agenda/todo_agenda_page.dart';
import 'package:secondloop/features/actions/review/review_queue_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReviewReminderInAppFallbackPrefs.value.value =
        ReviewReminderInAppFallbackPrefs.defaultValue;
  });

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

  testWidgets(
      'shows in-app reminder when review queue reminder crosses while foreground',
      (tester) async {
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _pumpGateHarness(
      tester,
      todos: <Todo>[
        _reviewTodo(
            nextReviewAtMs:
                nowUtcMs + const Duration(seconds: 6).inMilliseconds),
      ],
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_banner')),
      findsOneWidget,
    );
  });

  testWidgets(
      'shows in-app reminder when due todo reminder crosses while foreground',
      (tester) async {
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _pumpGateHarness(
      tester,
      todos: <Todo>[
        _dueTodo(dueAtMs: nowUtcMs + const Duration(seconds: 6).inMilliseconds),
      ],
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_banner')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_open')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TodoAgendaPage), findsOneWidget);
  });

  testWidgets('plays alert sound when in-app reminder appears', (tester) async {
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    var played = 0;

    await _pumpGateHarness(
      tester,
      todos: <Todo>[
        _reviewTodo(
            nextReviewAtMs:
                nowUtcMs + const Duration(seconds: 6).inMilliseconds),
      ],
      inAppFallbackAlertSound: () async {
        played += 1;
      },
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_banner')),
      findsOneWidget,
    );
    expect(played, 1);
  });

  testWidgets('does not show review-queue reminder for overdue item on launch',
      (tester) async {
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _pumpGateHarness(
      tester,
      todos: <Todo>[
        _reviewTodo(
            nextReviewAtMs:
                nowUtcMs - const Duration(minutes: 1).inMilliseconds),
      ],
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_banner')),
      findsNothing,
    );
  });

  testWidgets('does not show due reminder for overdue item on launch',
      (tester) async {
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _pumpGateHarness(
      tester,
      todos: <Todo>[
        _dueTodo(dueAtMs: nowUtcMs - const Duration(minutes: 1).inMilliseconds),
      ],
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_banner')),
      findsNothing,
    );
  });

  testWidgets('does not show in-app reminder when fallback setting is disabled',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ReviewReminderInAppFallbackPrefs.prefsKey: false,
    });

    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _pumpGateHarness(
      tester,
      todos: <Todo>[
        _reviewTodo(
            nextReviewAtMs:
                nowUtcMs + const Duration(seconds: 6).inMilliseconds),
      ],
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_banner')),
      findsNothing,
    );
  });
}

Future<_GateHarness> _pumpGateHarness(
  WidgetTester tester, {
  bool schedulerSupportsSystemNotifications = true,
  List<Todo>? todos,
  InAppFallbackAlertSoundCallback? inAppFallbackAlertSound,
}) async {
  final scheduler = _FakeScheduler(
    supportsSystemNotifications: schedulerSupportsSystemNotifications,
  );
  final effectiveTodos = todos ?? _defaultTodos;
  final navigatorKey = GlobalKey<NavigatorState>();

  await tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: AppBackendScope(
          backend: _Backend(todos: effectiveTodos),
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: ReviewReminderNotificationsGate(
              navigatorKey: navigatorKey,
              schedulerFactory: (onTap) {
                scheduler.onTap = onTap;
                return scheduler;
              },
              inAppFallbackAlertSound: inAppFallbackAlertSound,
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

Todo _reviewTodo({required int nextReviewAtMs}) {
  return Todo(
    id: 'todo:review',
    title: 'review this',
    status: 'inbox',
    createdAtMs: 1,
    updatedAtMs: 1,
    reviewStage: 0,
    nextReviewAtMs: nextReviewAtMs,
  );
}

Todo _dueTodo({required int dueAtMs}) {
  return Todo(
    id: 'todo:due',
    title: 'due soon',
    status: 'open',
    dueAtMs: dueAtMs,
    createdAtMs: 1,
    updatedAtMs: 1,
    reviewStage: null,
    nextReviewAtMs: null,
  );
}

final class _GateHarness {
  const _GateHarness({required this.scheduler});

  final _FakeScheduler scheduler;
}

final class _FakeScheduler implements ReviewReminderNotificationScheduler {
  _FakeScheduler({required this.supportsSystemNotifications});

  @override
  final bool supportsSystemNotifications;

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

final _defaultTodos = <Todo>[
  _reviewTodo(nextReviewAtMs: 60 * 60 * 1000),
];

final class _Backend extends TestAppBackend {
  _Backend({required this.todos});

  final List<Todo> todos;

  @override
  Future<List<Todo>> listTodos(Uint8List key) async {
    return todos;
  }
}
