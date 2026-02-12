import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../i18n/strings.g.dart';
import 'review_notification_plan.dart';

typedef NotificationTapHandler = void Function(String? payload);

abstract interface class ReviewReminderNotificationScheduler {
  bool get supportsSystemNotifications;

  Future<void> ensureInitialized();

  Future<void> schedule(ReviewReminderPlan plan);

  Future<void> cancel();
}

final class FlutterLocalNotificationsReviewReminderScheduler
    implements ReviewReminderNotificationScheduler {
  FlutterLocalNotificationsReviewReminderScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    NotificationTapHandler? onTap,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _onTap = onTap;

  static const int notificationIdBase = 2026021100;
  static const String reviewQueuePayloadPrefix = 'review_queue:';

  static const String androidNotificationIcon = 'ic_stat_notify';

  static const String _androidChannelId = 'review_reminders_v1';
  static const String _androidChannelName = 'Review reminders';
  static const String _androidChannelDescription =
      'Reminders for pending todo reviews';

  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationTapHandler? _onTap;

  bool _initialized = false;
  bool _available = true;
  bool _timeZoneInitialized = false;

  @override
  bool get supportsSystemNotifications => _available;
  final Set<int> _managedNotificationIds = <int>{};

  @override
  Future<void> ensureInitialized() async {
    if (_initialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings(androidNotificationIcon),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );

    try {
      await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (response) {
          _onTap?.call(response.payload);
        },
      );

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final launchResponse = launchDetails?.notificationResponse;
      if (launchDetails?.didNotificationLaunchApp == true) {
        _onTap?.call(launchResponse?.payload);
      }
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

      final dynamic canScheduleExactNotifications =
          await androidImpl?.canScheduleExactNotifications();
      if (canScheduleExactNotifications == false) {
        await androidImpl?.requestExactAlarmsPermission();
      }
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

    await _cancelManagedNotifications();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: _androidChannelDescription,
        importance: Importance.max,
        priority: Priority.high,
        icon: androidNotificationIcon,
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

    for (var i = 0; i < plan.items.length; i++) {
      final item = plan.items[i];
      final notificationId = notificationIdBase + i;
      final scheduledAtUtc = DateTime.fromMillisecondsSinceEpoch(
        item.scheduleAtUtcMs,
        isUtc: true,
      );
      final scheduleAt = tz.TZDateTime.from(scheduledAtUtc, tz.local);
      final payload = item.kind == ReviewReminderItemKind.reviewQueue
          ? '$reviewQueuePayloadPrefix${item.todoId}'
          : null;
      final title = item.kind == ReviewReminderItemKind.reviewQueue
          ? t.actions.reviewQueue.title
          : t.actions.agenda.title;

      await _scheduleSingleNotification(
        notificationId: notificationId,
        title: title,
        body: item.todoTitle,
        scheduleAt: scheduleAt,
        details: details,
        payload: payload,
      );
    }
  }

  Future<void> _scheduleSingleNotification({
    required int notificationId,
    required String title,
    required String body,
    required tz.TZDateTime scheduleAt,
    required NotificationDetails details,
    required String? payload,
  }) async {
    Future<void> scheduleWithMode(AndroidScheduleMode mode) {
      return _plugin.zonedSchedule(
        notificationId,
        title,
        body,
        scheduleAt,
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: mode,
        payload: payload,
      );
    }

    try {
      await scheduleWithMode(AndroidScheduleMode.exactAllowWhileIdle);
      _managedNotificationIds.add(notificationId);
      return;
    } on MissingPluginException {
      _available = false;
      return;
    } on PlatformException {
      // Exact alarms can be blocked on newer Android versions.
    } catch (_) {
      return;
    }

    try {
      await scheduleWithMode(AndroidScheduleMode.inexactAllowWhileIdle);
      _managedNotificationIds.add(notificationId);
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }

  @override
  Future<void> cancel() async {
    await ensureInitialized();
    if (!_available) return;

    await _cancelManagedNotifications();
  }

  Future<void> _cancelManagedNotifications() async {
    if (_managedNotificationIds.isEmpty) {
      for (var i = 0; i < kReviewReminderMaxItems; i++) {
        await _cancelNotification(notificationIdBase + i);
      }
      return;
    }

    for (final notificationId in _managedNotificationIds) {
      await _cancelNotification(notificationId);
    }
    _managedNotificationIds.clear();
  }

  Future<void> _cancelNotification(int notificationId) async {
    try {
      await _plugin.cancel(notificationId);
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }
  }
}
