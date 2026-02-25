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
import 'package:secondloop/core/sync/sync_engine.dart';
import 'package:secondloop/core/sync/sync_engine_gate.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_page.dart';
import 'package:secondloop/src/rust/db.dart';

import 'test_backend.dart';
import 'test_i18n.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReviewReminderInAppFallbackPrefs.value.value =
        ReviewReminderInAppFallbackPrefs.defaultValue;
  });

  testWidgets('tap notification payload opens task hub page', (tester) async {
    final harness = await _pumpGateHarness(tester);

    harness.scheduler.onTap?.call(
      '${FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix}todo:1',
    );

    await tester.pumpAndSettle();

    expect(find.byType(TaskHubPage), findsOneWidget);
  });

  testWidgets('ignores unrelated notification payload', (tester) async {
    final harness = await _pumpGateHarness(tester);

    harness.scheduler.onTap?.call('todo:1');

    await tester.pumpAndSettle();

    expect(find.byType(TaskHubPage), findsNothing);
  });

  testWidgets('ignores duplicate taps while task hub page is open',
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
      find.byType(TaskHubPage, skipOffstage: false),
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

    expect(find.byType(TaskHubPage), findsOneWidget);
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

  testWidgets('dismissing in-app reminder keeps the same source hidden',
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

    final bannerFinder =
        find.byKey(const ValueKey('review_reminder_in_app_fallback_banner'));
    expect(bannerFinder, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_dismiss')),
    );
    await tester.pumpAndSettle();

    expect(bannerFinder, findsNothing);

    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();

    expect(bannerFinder, findsNothing);
  });

  testWidgets('dismissed reminder stays hidden across refresh', (tester) async {
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final harness = await _pumpGateHarness(
      tester,
      syncEngine: _buildManualSyncEngine(),
      todos: <Todo>[
        _dueTodo(
          dueAtMs: nowUtcMs + const Duration(seconds: 2).inMilliseconds,
        ),
      ],
    );

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    final bannerFinder =
        find.byKey(const ValueKey('review_reminder_in_app_fallback_banner'));
    expect(bannerFinder, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_dismiss')),
    );
    await tester.pumpAndSettle();
    expect(bannerFinder, findsNothing);

    harness.syncEngine!.notifyExternalChange();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(bannerFinder, findsNothing);
  });

  testWidgets(
      'dismissed due reminder stays hidden when source timestamp drifts',
      (tester) async {
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final initialDueAtMs = nowUtcMs + const Duration(seconds: 6).inMilliseconds;
    final harness = await _pumpGateHarness(
      tester,
      syncEngine: _buildManualSyncEngine(),
      todos: <Todo>[_dueTodo(dueAtMs: initialDueAtMs)],
    );

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    final bannerFinder =
        find.byKey(const ValueKey('review_reminder_in_app_fallback_banner'));
    expect(bannerFinder, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_dismiss')),
    );
    await tester.pumpAndSettle();
    expect(bannerFinder, findsNothing);

    harness.backend.todos
      ..clear()
      ..add(_dueTodo(dueAtMs: initialDueAtMs + 1));

    harness.syncEngine!.notifyExternalChange();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(bannerFinder, findsNothing);
  });

  testWidgets('shows in-app reminder while app is inactive', (tester) async {
    final nowUtcMs = DateTime.now().toUtc().millisecondsSinceEpoch;

    await _pumpGateHarness(
      tester,
      todos: <Todo>[
        _reviewTodo(
            nextReviewAtMs:
                nowUtcMs + const Duration(seconds: 6).inMilliseconds),
      ],
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('review_reminder_in_app_fallback_banner')),
      findsOneWidget,
    );
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
  SyncEngine? syncEngine,
  InAppFallbackAlertSoundCallback? inAppFallbackAlertSound,
}) async {
  final scheduler = _FakeScheduler(
    supportsSystemNotifications: schedulerSupportsSystemNotifications,
  );
  final effectiveTodos = todos ?? _defaultTodos;
  final navigatorKey = GlobalKey<NavigatorState>();

  final gate = ReviewReminderNotificationsGate(
    navigatorKey: navigatorKey,
    schedulerFactory: (onTap) {
      scheduler.onTap = onTap;
      return scheduler;
    },
    inAppFallbackAlertSound: inAppFallbackAlertSound,
    child: const Scaffold(body: Text('home')),
  );
  final content = syncEngine == null
      ? gate
      : SyncEngineScope(engine: syncEngine, child: gate);
  final backend = _Backend(todos: effectiveTodos);

  await tester.pumpWidget(
    wrapWithI18n(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: AppBackendScope(
          backend: backend,
          child: SessionScope(
            sessionKey: Uint8List.fromList(List<int>.filled(32, 1)),
            lock: () {},
            child: content,
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 600));

  expect(scheduler.ensureInitializedCalls, greaterThan(0));

  return _GateHarness(
    scheduler: scheduler,
    syncEngine: syncEngine,
    backend: backend,
  );
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
  const _GateHarness({
    required this.scheduler,
    required this.syncEngine,
    required this.backend,
  });

  final _FakeScheduler scheduler;
  final SyncEngine? syncEngine;
  final _Backend backend;
}

SyncEngine _buildManualSyncEngine() {
  return SyncEngine(
    syncRunner: _NoopSyncRunner(),
    loadConfig: () async => null,
  );
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

final class _NoopSyncRunner implements SyncRunner {
  @override
  Future<int> pull(SyncConfig config) async {
    return 0;
  }

  @override
  Future<int> push(SyncConfig config) async {
    return 0;
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
