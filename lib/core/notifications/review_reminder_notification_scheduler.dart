import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'review_notification_plan.dart';

abstract interface class ReviewReminderNotificationScheduler {
  Future<void> ensureInitialized();

  Future<void> schedule(ReviewReminderPlan plan);

  Future<void> cancel();
}

final class FlutterLocalNotificationsReviewReminderScheduler
    implements ReviewReminderNotificationScheduler {
  FlutterLocalNotificationsReviewReminderScheduler({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int notificationId = 2026021101;
  static const String _androidChannelId = 'review_reminders_v1';
  static const String _androidChannelName = 'Review reminders';
  static const String _androidChannelDescription =
      'Reminders for pending todo reviews';

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;
  bool _available = true;
  bool _timeZoneInitialized = false;

  @override
  Future<void> ensureInitialized() async {
    if (_initialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );

    try {
      await _plugin.initialize(initializationSettings);
    } on MissingPluginException {
      _available = false;
      _initialized = true;
      return;
    }

    await _requestPermissionsBestEffort();
    _configureTimeZone();
    _initialized = true;
  }

  Future<void> _requestPermissionsBestEffort() async {
    try {
      final dynamic androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
    } catch (_) {
      // ignore
    }

    try {
      final dynamic iosImpl = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (_) {
      // ignore
    }

    try {
      final dynamic macosImpl = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      await macosImpl?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // ignore
    }
  }

  void _configureTimeZone() {
    if (_timeZoneInitialized) return;
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.UTC);
      _timeZoneInitialized = true;
    } catch (_) {
      // ignore
    }
  }

  @override
  Future<void> schedule(ReviewReminderPlan plan) async {
    await ensureInitialized();
    if (!_available) return;

    _configureTimeZone();
    if (!_timeZoneInitialized) return;

    final scheduledAtUtc =
        DateTime.fromMillisecondsSinceEpoch(plan.scheduleAtUtcMs, isUtc: true);
    final scheduleAt = tz.TZDateTime.from(scheduledAtUtc, tz.local);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: _androidChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final body = plan.pendingCount == 1
        ? 'You have 1 task waiting for review.'
        : 'You have ${plan.pendingCount} tasks waiting for review.';

    try {
      await _plugin.zonedSchedule(
        notificationId,
        'Review reminder',
        body,
        scheduleAt,
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'review_queue',
      );
    } on MissingPluginException {
      // ignore
    }
  }

  @override
  Future<void> cancel() async {
    await ensureInitialized();
    if (!_available) return;

    try {
      await _plugin.cancel(notificationId);
    } on MissingPluginException {
      // ignore
    }
  }
}
