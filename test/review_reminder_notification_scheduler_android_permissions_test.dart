import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secondloop/core/notifications/review_reminder_notification_scheduler.dart';

void main() {
  test('ensureInitialized requests exact alarm permission when unavailable',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

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
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

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
}
