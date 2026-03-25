import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:secondloop/core/notifications/review_notification_plan.dart';
import 'package:secondloop/core/notifications/review_reminder_notification_scheduler.dart';

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

  test('same todo keeps stable notification id across reminder updates', () {
    const first = ReviewReminderItem(
      todoId: 'todo:1',
      todoTitle: 'one',
      sourceAtUtcMs: 1000,
      scheduleAtUtcMs: 2000,
      kind: ReviewReminderItemKind.reviewQueue,
    );
    const second = ReviewReminderItem(
      todoId: 'todo:1',
      todoTitle: 'one',
      sourceAtUtcMs: 3000,
      scheduleAtUtcMs: 4000,
      kind: ReviewReminderItemKind.reviewQueue,
    );
    const other = ReviewReminderItem(
      todoId: 'todo:2',
      todoTitle: 'two',
      sourceAtUtcMs: 3000,
      scheduleAtUtcMs: 4000,
      kind: ReviewReminderItemKind.reviewQueue,
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

  test('schedule adds android quick actions and todo payload', () async {
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
      FlutterLocalNotificationsReviewReminderScheduler.androidDoneActionId,
      FlutterLocalNotificationsReviewReminderScheduler.androidDismissActionId,
    ]);
  });

  test('notification details add Windows quick actions and keep payload', () {
    const item = ReviewReminderItem(
      todoId: 'todo:review',
      todoTitle: 'review this',
      sourceAtUtcMs: 10000,
      scheduleAtUtcMs: 20000,
      kind: ReviewReminderItemKind.reviewQueue,
    );
    final payload =
        FlutterLocalNotificationsReviewReminderScheduler.encodePayload(
      item,
    );

    final details = FlutterLocalNotificationsReviewReminderScheduler
            .notificationDetailsForItem(item)
        .windows;

    expect(details, isNotNull);
    expect(details!.actions.length, 2);
    expect(details.actions.map((action) => action.arguments), <String>[
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.androidDoneActionId,
        payload,
      ),
      FlutterLocalNotificationsReviewReminderScheduler
          .encodeWindowsQuickActionArguments(
        FlutterLocalNotificationsReviewReminderScheduler.androidDismissActionId,
        payload,
      ),
    ]);
  });

  test('eventFromResponse decodes Windows quick action arguments', () {
    const payload =
        '${FlutterLocalNotificationsReviewReminderScheduler.reviewQueuePayloadPrefix}todo:review';
    final encoded = FlutterLocalNotificationsReviewReminderScheduler
        .encodeWindowsQuickActionArguments(
      FlutterLocalNotificationsReviewReminderScheduler.androidDoneActionId,
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
      FlutterLocalNotificationsReviewReminderScheduler.androidDoneActionId,
    );
  });

  test('legacy Windows app id list excludes current app id', () {
    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .legacyWindowsAppUserModelIds(
        'com.secondloop.secondloop',
      ),
      <String>['com.secondloop.secondloopdev'],
    );
    expect(
      FlutterLocalNotificationsReviewReminderScheduler
          .legacyWindowsAppUserModelIds(
        'com.secondloop.secondloopdev',
      ),
      <String>['com.secondloop.secondloop'],
    );
  });
}

final class _FakeAndroidNotificationsPlugin
    extends AndroidFlutterLocalNotificationsPlugin {
  _FakeAndroidNotificationsPlugin({
    required this.canScheduleExactNotificationsResult,
  });

  final bool canScheduleExactNotificationsResult;

  int initializeCalls = 0;
  int getNotificationAppLaunchDetailsCalls = 0;
  int requestNotificationsPermissionCalls = 0;
  int canScheduleExactNotificationsCalls = 0;
  int requestExactAlarmsPermissionCalls = 0;
  int zonedScheduleCalls = 0;
  int? lastId;
  String? lastPayload;
  AndroidNotificationDetails? lastNotificationDetails;

  @override
  Future<bool> initialize(
    AndroidInitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls += 1;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    getNotificationAppLaunchDetailsCalls += 1;
    return null;
  }

  @override
  Future<bool?> requestNotificationsPermission() async {
    requestNotificationsPermissionCalls += 1;
    return true;
  }

  @override
  Future<bool?> canScheduleExactNotifications() async {
    canScheduleExactNotificationsCalls += 1;
    return canScheduleExactNotificationsResult;
  }

  @override
  Future<bool?> requestExactAlarmsPermission() async {
    requestExactAlarmsPermissionCalls += 1;
    return true;
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    return const <PendingNotificationRequest>[];
  }

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    AndroidNotificationDetails? notificationDetails, {
    required AndroidScheduleMode scheduleMode,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    zonedScheduleCalls += 1;
    lastId = id;
    lastPayload = payload;
    lastNotificationDetails = notificationDetails;
  }
}
