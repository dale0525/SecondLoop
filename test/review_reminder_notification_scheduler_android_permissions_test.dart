// ignore_for_file: depend_on_referenced_packages

library review_reminder_notification_scheduler_android_permissions_test;

import 'dart:ffi' as ffi;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications_windows/src/plugin/ffi.dart'
    as windows_plugin;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:secondloop/core/notifications/review_notification_plan.dart';
import 'package:secondloop/core/notifications/review_reminder_notification_scheduler.dart';
import 'package:secondloop/features/actions/task_hub/task_hub_quick_actions.dart';

part 'support/review_reminder_notification_scheduler_test_fakes.dart';

void main() {
  test('ensureInitialized requests exact alarm permission when unavailable',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final androidPlugin = _FakeAndroidNotificationsPlugin(
      canScheduleExactNotificationsResult: false,
    );
    FlutterLocalNotificationsPlatform.instance = androidPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await scheduler.ensureInitialized();

    expect(androidPlugin.initializeCalls, 1);
    expect(androidPlugin.getNotificationAppLaunchDetailsCalls, 1);
    expect(androidPlugin.requestNotificationsPermissionCalls, 1);
    expect(androidPlugin.canScheduleExactNotificationsCalls, 1);
    expect(androidPlugin.requestExactAlarmsPermissionCalls, 1);
  });

  test('ensureInitialized skips exact alarm request when already granted',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final androidPlugin = _FakeAndroidNotificationsPlugin(
      canScheduleExactNotificationsResult: true,
    );
    FlutterLocalNotificationsPlatform.instance = androidPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await scheduler.ensureInitialized();

    expect(androidPlugin.requestNotificationsPermissionCalls, 1);
    expect(androidPlugin.canScheduleExactNotificationsCalls, 1);
    expect(androidPlugin.requestExactAlarmsPermissionCalls, 0);
  });

  test(
      'ensureInitialized disables notifications when the current platform implementation is missing',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    FlutterLocalNotificationsPlatform.instance =
        _FallbackNotificationsPlatform();

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await scheduler.ensureInitialized();

    expect(scheduler.supportsSystemNotifications, isFalse);
  });

  test(
      'ensureInitialized marks notifications unavailable after init returns false and restores them on retry',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final windowsPlugin = _FakeAndroidNotificationsPlugin(
      canScheduleExactNotificationsResult: true,
      initializeResults: <bool>[false, true],
    );
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await expectLater(scheduler.ensureInitialized(), throwsStateError);
    expect(scheduler.supportsSystemNotifications, isFalse);

    await scheduler.ensureInitialized();

    expect(windowsPlugin.initializeCalls, 2);
    expect(windowsPlugin.getNotificationAppLaunchDetailsCalls, 1);
    expect(scheduler.supportsSystemNotifications, isTrue);
  });

  test(
      'schedule reports Windows scheduling failures and disables notifications',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final windowsPlugin = _ThrowingWindowsNotificationsPlugin();
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[
          ReviewReminderItem(
            todoId: 'todo:review',
            todoTitle: 'review this',
            sourceAtUtcMs: 10000,
            scheduleAtUtcMs: 20000,
            kind: ReviewReminderItemKind.reviewQueue,
            todoStatus: 'open',
          ),
        ],
      ),
    );

    expect(windowsPlugin.initializeCalls, 1);
    expect(windowsPlugin.zonedScheduleCalls, 1);
    expect(scheduler.supportsSystemNotifications, isFalse);
    expect(errors, hasLength(1));
    expect(
        errors.single.exceptionAsString(), contains('native schedule failed'));
  });

  test(
      'schedule retries Windows initialization after a transient scheduling failure',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final windowsPlugin = _ResetRequiredWindowsNotificationsPlugin();
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const item = ReviewReminderItem(
      todoId: 'todo:retry',
      todoTitle: 'retry this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[item],
      ),
    );

    expect(windowsPlugin.initializeAttempts, 1);
    expect(windowsPlugin.nativeInitializeCalls, 1);
    expect(windowsPlugin.zonedScheduleCalls, 1);
    expect(scheduler.supportsSystemNotifications, isFalse);

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[item],
      ),
    );

    expect(windowsPlugin.initializeAttempts, 2);
    expect(windowsPlugin.nativeInitializeCalls, 2);
    expect(windowsPlugin.disposeCalls, 1);
    expect(windowsPlugin.zonedScheduleCalls, 2);
    expect(scheduler.supportsSystemNotifications, isTrue);
    expect(errors, hasLength(1));
  });

  test(
      'schedule stops further Windows notifications and rolls back this batch after a failure',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final windowsPlugin = _SequencedWindowsNotificationsPlugin(
      scheduleOutcomes: <_WindowsScheduleOutcome>[
        _WindowsScheduleOutcome.success,
        _WindowsScheduleOutcome.throwError,
        _WindowsScheduleOutcome.success,
      ],
    );
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const first = ReviewReminderItem(
      todoId: 'todo:rollback-1',
      todoTitle: 'first',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const second = ReviewReminderItem(
      todoId: 'todo:rollback-2',
      todoTitle: 'second',
      sourceAtUtcMs: 10001,
      scheduleAtUtcMs: 20001,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const third = ReviewReminderItem(
      todoId: 'todo:rollback-3',
      todoTitle: 'third',
      sourceAtUtcMs: 10002,
      scheduleAtUtcMs: 20002,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 3,
        items: <ReviewReminderItem>[first, second, third],
      ),
    );

    final firstId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      first,
    );
    final thirdId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      third,
    );

    expect(windowsPlugin.zonedScheduleCalls, 2);
    expect(windowsPlugin.scheduledIds, <int>[firstId]);
    expect(windowsPlugin.cancelledIds, contains(firstId));
    expect(windowsPlugin.cancelledIds, isNot(contains(thirdId)));
    expect(errors, hasLength(1));
  });

  test('schedule restores the previous Windows batch when replacing it fails',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final windowsPlugin = _SequencedWindowsNotificationsPlugin(
      scheduleOutcomes: <_WindowsScheduleOutcome>[
        _WindowsScheduleOutcome.success,
        _WindowsScheduleOutcome.success,
        _WindowsScheduleOutcome.throwError,
        _WindowsScheduleOutcome.success,
      ],
    );
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const previous = ReviewReminderItem(
      todoId: 'todo:previous',
      todoTitle: 'previous',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const replacementOne = ReviewReminderItem(
      todoId: 'todo:new-1',
      todoTitle: 'new one',
      sourceAtUtcMs: 10001,
      scheduleAtUtcMs: 20001,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const replacementTwo = ReviewReminderItem(
      todoId: 'todo:new-2',
      todoTitle: 'new two',
      sourceAtUtcMs: 10002,
      scheduleAtUtcMs: 20002,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[previous],
      ),
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 2,
        items: <ReviewReminderItem>[replacementOne, replacementTwo],
      ),
    );

    final previousId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      previous,
    );
    final replacementOneId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      replacementOne,
    );
    final replacementTwoId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      replacementTwo,
    );

    expect(windowsPlugin.pendingIds, <int>{previousId});
    expect(windowsPlugin.cancelledIds, contains(previousId));
    expect(windowsPlugin.cancelledIds, contains(replacementOneId));
    expect(windowsPlugin.pendingIds, isNot(contains(replacementOneId)));
    expect(windowsPlugin.pendingIds, isNot(contains(replacementTwoId)));
    expect(errors, hasLength(1));
  });

  test(
      'schedule restores discovered Windows notifications after a cold-start replacement failure',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    const previous = ReviewReminderItem(
      todoId: 'todo:cold-start-previous',
      todoTitle: 'previous',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const replacement = ReviewReminderItem(
      todoId: 'todo:cold-start-new',
      todoTitle: 'replacement',
      sourceAtUtcMs: 10001,
      scheduleAtUtcMs: 20001,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    final previousId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      previous,
    );
    final windowsPlugin = _SequencedWindowsNotificationsPlugin(
      scheduleOutcomes: <_WindowsScheduleOutcome>[
        _WindowsScheduleOutcome.throwError,
        _WindowsScheduleOutcome.success,
      ],
      initialPendingItems: const <ReviewReminderItem>[previous],
    );
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    final didSchedule = await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[replacement],
      ),
    );

    expect(didSchedule, isFalse);
    expect(windowsPlugin.cancelledIds, isNot(contains(previousId)));
    expect(windowsPlugin.pendingIds, <int>{previousId});
    expect(errors, hasLength(1));
  });

  test(
      'schedule rolls back partially restored Windows notifications when previous plan restore fails',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final windowsPlugin = _SequencedWindowsNotificationsPlugin(
      scheduleOutcomes: <_WindowsScheduleOutcome>[
        _WindowsScheduleOutcome.success,
        _WindowsScheduleOutcome.success,
        _WindowsScheduleOutcome.throwError,
        _WindowsScheduleOutcome.success,
        _WindowsScheduleOutcome.throwError,
      ],
    );
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const previousOne = ReviewReminderItem(
      todoId: 'todo:restore-previous-1',
      todoTitle: 'previous one',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const previousTwo = ReviewReminderItem(
      todoId: 'todo:restore-previous-2',
      todoTitle: 'previous two',
      sourceAtUtcMs: 10001,
      scheduleAtUtcMs: 20001,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const replacement = ReviewReminderItem(
      todoId: 'todo:restore-replacement',
      todoTitle: 'replacement',
      sourceAtUtcMs: 10002,
      scheduleAtUtcMs: 20002,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 2,
        items: <ReviewReminderItem>[previousOne, previousTwo],
      ),
    );

    final didSchedule = await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[replacement],
      ),
    );

    final previousOneId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      previousOne,
    );
    final previousTwoId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      previousTwo,
    );

    expect(didSchedule, isFalse);
    expect(windowsPlugin.pendingIds, isEmpty);
    expect(windowsPlugin.cancelledIds, contains(previousOneId));
    expect(windowsPlugin.cancelledIds, contains(previousTwoId));
    expect(
      windowsPlugin.cancelledIds.where((id) => id == previousOneId).length,
      greaterThanOrEqualTo(2),
    );
    expect(errors, hasLength(2));
  });

  test(
      'schedule keeps current Windows notifications when cold-start diff is empty',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final windowsPlugin = _SequencedWindowsNotificationsPlugin(
      scheduleOutcomes: <_WindowsScheduleOutcome>[
        _WindowsScheduleOutcome.success
      ],
      initialPendingItems: const <ReviewReminderItem>[
        ReviewReminderItem(
          todoId: 'todo:cold-start-same',
          todoTitle: 'same item',
          sourceAtUtcMs: 10000,
          scheduleAtUtcMs: 20000,
          kind: ReviewReminderItemKind.reviewQueue,
          todoStatus: 'open',
        ),
      ],
    );
    FlutterLocalNotificationsPlatform.instance = windowsPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const item = ReviewReminderItem(
      todoId: 'todo:cold-start-same',
      todoTitle: 'same item',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    final itemId =
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
      item,
    );

    final didSchedule = await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[item],
      ),
    );

    expect(didSchedule, isTrue);
    expect(windowsPlugin.pendingIds, <int>{itemId});
    expect(windowsPlugin.cancelledIds, isEmpty);
  });

  test('schedule reports generic Android scheduling errors as failures',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = errors.add;

    final androidPlugin = _FakeAndroidNotificationsPlugin(
      canScheduleExactNotificationsResult: true,
      scheduleError: Exception('android schedule failed'),
    );
    FlutterLocalNotificationsPlatform.instance = androidPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    final didSchedule = await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[
          ReviewReminderItem(
            todoId: 'todo:android-error',
            todoTitle: 'android failure',
            sourceAtUtcMs: 10000,
            scheduleAtUtcMs: 20000,
            kind: ReviewReminderItemKind.reviewQueue,
            todoStatus: 'open',
          ),
        ],
      ),
    );

    expect(didSchedule, isFalse);
    expect(androidPlugin.zonedScheduleCalls, 1);
    expect(errors, hasLength(1));
  });

  test('same todo keeps stable notification id across reminder updates', () {
    const first = ReviewReminderItem(
      todoId: 'todo:1',
      todoTitle: 'one',
      sourceAtUtcMs: 1000,
      scheduleAtUtcMs: 2000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    const second = ReviewReminderItem(
      todoId: 'todo:1',
      todoTitle: 'one',
      sourceAtUtcMs: 3000,
      scheduleAtUtcMs: 4000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'in_progress',
    );
    const other = ReviewReminderItem(
      todoId: 'todo:2',
      todoTitle: 'two',
      sourceAtUtcMs: 3000,
      scheduleAtUtcMs: 4000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    expect(
      FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
        first,
      ),
      FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
        second,
      ),
    );
    expect(
      FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
        first,
      ),
      isNot(
        FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
          other,
        ),
      ),
    );
  });

  test('open reminders expose the same quick actions as task hub', () {
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .notificationQuickActionsForItem(item),
      <TaskHubQuickAction>[
        TaskHubQuickAction.start,
        TaskHubQuickAction.tomorrow,
        TaskHubQuickAction.today,
        TaskHubQuickAction.done,
      ],
    );
  });

  test('open reminders trim Android quick actions to the visible limit', () {
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .androidNotificationQuickActionsForItem(item),
      <TaskHubQuickAction>[
        TaskHubQuickAction.start,
        TaskHubQuickAction.done,
        TaskHubQuickAction.tomorrow,
      ],
    );
  });

  test('in-progress reminders expose the same quick actions as task hub', () {
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'in_progress',
    );

    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .notificationQuickActionsForItem(item),
      <TaskHubQuickAction>[
        TaskHubQuickAction.done,
        TaskHubQuickAction.tomorrow,
        TaskHubQuickAction.today,
      ],
    );
  });

  test('schedule adds Android quick actions matching task hub layout',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    final androidPlugin = _FakeAndroidNotificationsPlugin(
      canScheduleExactNotificationsResult: true,
    );
    FlutterLocalNotificationsPlatform.instance = androidPlugin;

    final scheduler = FlutterLocalNotificationsReviewReminderScheduler(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );

    await scheduler.schedule(
      const ReviewReminderPlan(
        pendingCount: 1,
        items: <ReviewReminderItem>[item],
      ),
    );

    expect(androidPlugin.zonedScheduleCalls, 1);
    expect(
      androidPlugin.lastPayload,
      '${FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix}todo:review',
    );
    expect(
      androidPlugin.lastId,
      FlutterLocalNotificationsReviewReminderScheduler.notificationIdForItem(
        item,
      ),
    );

    final actions = androidPlugin.lastNotificationDetails?.actions;
    expect(actions, isNotNull);
    expect(actions!.map((action) => action.id), <String>[
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.start,
      ),
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.done,
      ),
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.tomorrow,
      ),
    ]);
  });

  test('notification details add Windows quick actions matching task hub', () {
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
      todoStatus: 'open',
    );
    final payload =
        FlutterLocalNotificationsReviewReminderScheduler.encodePayload(
      item,
    );

    final details = FlutterLocalNotificationsReviewReminderScheduler
            .notificationDetailsForItem(item)
        .windows;

    expect(details, isNotNull);
    expect(details!.actions.length, 4);
    expect(details.actions.map((action) => action.arguments), <String>[
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
          TaskHubQuickAction.start,
        ),
        payload,
      ),
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
          TaskHubQuickAction.tomorrow,
        ),
        payload,
      ),
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
          TaskHubQuickAction.today,
        ),
        payload,
      ),
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
          TaskHubQuickAction.done,
        ),
        payload,
      ),
    ]);
  });

  test('eventFromResponse decodes Windows quick action arguments', () {
    const payload =
        '${FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix}todo:review';
    final encoded = FlutterLocalNotificationsReviewReminderScheduler
        .encodeWindowsQuickActionArguments(
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.done,
      ),
      payload,
    );

    final event =
        FlutterLocalNotificationsReviewReminderScheduler.eventFromResponse(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        payload: encoded,
        actionId: encoded,
      ),
    );

    expect(event.payload, payload);
    expect(
      event.actionId,
      FlutterLocalNotificationsReviewReminderScheduler.notificationActionId(
        TaskHubQuickAction.done,
      ),
    );
  });

  test('legacy Windows app id list does not treat active channels as legacy',
      () {
    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .legacyWindowsAppUserModelIds(
        'com.secondloop.secondloop',
      ),
      isEmpty,
    );
    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .legacyWindowsAppUserModelIds(
        'com.secondloop.secondloopdev',
      ),
      isEmpty,
    );
  });
}
