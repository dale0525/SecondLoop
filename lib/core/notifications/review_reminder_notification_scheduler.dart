import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../i18n/strings.g.dart';
import 'review_notification_plan.dart';

typedef NotificationTapHandler = void Function(
  ReviewReminderNotificationEvent event,
);

final class ReviewReminderNotificationEvent {
  const ReviewReminderNotificationEvent({
    required this.payload,
    this.actionId,
  });

  final String? payload;
  final String? actionId;
}

final class ReviewReminderNotificationPayload {
  const ReviewReminderNotificationPayload({
    required this.kind,
    required this.todoId,
  });

  final ReviewReminderItemKind kind;
  final String todoId;
}

abstract interface class ReviewReminderNotificationScheduler {
  bool get supportsSystemNotifications;

  Future<void> ensureInitialized();

  Future<bool> schedule(ReviewReminderPlan plan);

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
  static const int _managedNotificationIdModulo = 1000000;
  static const String reviewQueuePayloadPrefix = 'review_queue:';
  static const String dueTodoPayloadPrefix = 'due_todo:';

  static const String androidNotificationIcon = 'ic_stat_notify';

  static const String _androidChannelId = 'review_reminders_v1';
  static const String _androidChannelName = 'Review reminders';
  static const String _androidChannelDescription =
      'Reminders for pending todo reviews';
  static const String _windowsAppName = 'SecondLoop';
  static const String _windowsProdAppUserModelId = 'com.secondloop.secondloop';
  // Intentionally empty for the initial release.
  // Add superseded AUMIDs here if the Windows app identity changes later.
  static const Set<String> _windowsLegacyAppUserModelIds = <String>{};
  static const String _windowsAppUserModelId = String.fromEnvironment(
    'SECONDLOOP_APP_ID',
    defaultValue: _windowsProdAppUserModelId,
  );
  static const String _windowsGuid = 'd49b5b4a-0ea5-4e31-b5c9-945cc5405f59';
  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationTapHandler? _onTap;

  bool _initialized = false;
  bool _available = true;
  bool _timeZoneInitialized = false;
  ReviewReminderPlan? _lastSuccessfulPlan;

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
      windows: WindowsInitializationSettings(
        appName: _windowsAppName,
        appUserModelId: _windowsAppUserModelId,
        guid: _windowsGuid,
      ),
    );

    try {
      final didInitialize = await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (response) {
          _onTap?.call(eventFromResponse(response));
        },
      );
      if (didInitialize == null) {
        _available = false;
        _initialized = true;
        return;
      }
      if (didInitialize != true) {
        _available = false;
        throw StateError(
          'Flutter Local Notifications failed to initialize system notifications',
        );
      }

      await _cleanupLegacyWindowsArtifactsBestEffort();

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final launchResponse = launchDetails?.notificationResponse;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchResponse != null) {
        _onTap?.call(eventFromResponse(launchResponse));
      }
    } on MissingPluginException {
      _available = false;
      _initialized = true;
      return;
    }

    await _requestPermissionsBestEffort();
    _configureTimeZone();
    _available = true;
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

  Future<void> _cleanupLegacyWindowsArtifactsBestEffort() async {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    try {
      final windowsImpl = _plugin.resolvePlatformSpecificImplementation<
          FlutterLocalNotificationsWindows>();
      if (windowsImpl == null) {
        return;
      }
      for (final legacyAumid
          in legacyWindowsAppUserModelIds(_windowsAppUserModelId)) {
        await windowsImpl.cleanupAumidArtifacts(legacyAumid);
      }
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
  Future<bool> schedule(ReviewReminderPlan plan) async {
    await ensureInitialized();
    if (!_available) return false;

    _configureTimeZone();
    if (!_timeZoneInitialized) return false;

    final previousPlan = _lastSuccessfulPlan;
    final isWindowsColdStart =
        defaultTargetPlatform == TargetPlatform.windows && previousPlan == null;
    final existingWindowsNotificationIds =
        isWindowsColdStart ? await _discoverManagedNotificationIds() : <int>{};
    var completed = true;
    if (!isWindowsColdStart) {
      await _cancelManagedNotifications();
    }
    final scheduledThisBatch = <int>[];

    for (var i = 0; i < plan.items.length; i++) {
      final item = plan.items[i];
      final notificationId = notificationIdForItem(item);
      final scheduledAtUtc = DateTime.fromMillisecondsSinceEpoch(
        item.scheduleAtUtcMs,
        isUtc: true,
      );
      final scheduleAt = tz.TZDateTime.from(scheduledAtUtc, tz.local);
      final payload = encodePayload(item);
      final title = item.kind == ReviewReminderItemKind.reviewQueue
          ? t.actions.reviewQueue.title
          : t.actions.agenda.title;
      final details = notificationDetailsForItem(item);

      final didSchedule = await _scheduleSingleNotification(
        notificationId: notificationId,
        title: title,
        body: item.todoTitle,
        scheduleAt: scheduleAt,
        details: details,
        payload: payload,
      );
      if (!didSchedule) {
        completed = false;
        await _rollbackScheduledBatch(scheduledThisBatch);
        if (defaultTargetPlatform == TargetPlatform.windows) {
          await _markWindowsNotificationsUnavailableForRetry();
        }
        if (!isWindowsColdStart) {
          final didRestore = await _restorePreviousPlanIfNeeded(previousPlan);
          if (!didRestore) {
            _lastSuccessfulPlan = null;
          }
        }
        break;
      }
      scheduledThisBatch.add(notificationId);
    }

    if (completed && _available) {
      if (isWindowsColdStart) {
        final staleExistingIds = existingWindowsNotificationIds.difference(
          scheduledThisBatch.toSet(),
        );
        if (staleExistingIds.isNotEmpty) {
          await _cancelNotificationBatch(staleExistingIds);
        }
      }
      _lastSuccessfulPlan = plan;
    }
    return completed && _available;
  }

  @visibleForTesting
  static int notificationIdForItem(ReviewReminderItem item) {
    final key = '${item.kind.name}:${item.todoId}';
    return notificationIdBase +
        (_stableHash(key) % _managedNotificationIdModulo);
  }

  @visibleForTesting
  static String encodePayload(ReviewReminderItem item) {
    final prefix = item.kind == ReviewReminderItemKind.reviewQueue
        ? reviewQueuePayloadPrefix
        : dueTodoPayloadPrefix;
    return '$prefix${item.todoId}';
  }

  @visibleForTesting
  static List<String> legacyWindowsAppUserModelIds(String currentAumid) {
    return _windowsLegacyAppUserModelIds
        .where((aumid) => aumid.isNotEmpty && aumid != currentAumid)
        .toList(growable: false);
  }

  @visibleForTesting
  static ReviewReminderNotificationEvent eventFromResponse(
    NotificationResponse response,
  ) {
    return ReviewReminderNotificationEvent(
      payload: response.payload,
      actionId: response.actionId,
    );
  }

  static ReviewReminderNotificationPayload? decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload.startsWith(reviewQueuePayloadPrefix)) {
      final todoId = payload.substring(reviewQueuePayloadPrefix.length);
      if (todoId.isEmpty) return null;
      return ReviewReminderNotificationPayload(
        kind: ReviewReminderItemKind.reviewQueue,
        todoId: todoId,
      );
    }
    if (payload.startsWith(dueTodoPayloadPrefix)) {
      final todoId = payload.substring(dueTodoPayloadPrefix.length);
      if (todoId.isEmpty) return null;
      return ReviewReminderNotificationPayload(
        kind: ReviewReminderItemKind.dueTodo,
        todoId: todoId,
      );
    }
    return null;
  }

  @visibleForTesting
  static NotificationDetails notificationDetailsForItem(
    ReviewReminderItem item,
  ) {
    return const NotificationDetails(
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
      windows: WindowsNotificationDetails(),
    );
  }

  Future<bool> _scheduleSingleNotification({
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
        androidScheduleMode: mode,
        payload: payload,
      );
    }

    try {
      await scheduleWithMode(AndroidScheduleMode.exactAllowWhileIdle);
      _managedNotificationIds.add(notificationId);
      return true;
    } on MissingPluginException {
      _available = false;
      return false;
    } on PlatformException {
      // Exact alarms can be blocked on newer Android versions.
    } catch (error, stackTrace) {
      _reportSchedulingError(
        error,
        stackTrace,
        notificationId: notificationId,
        payload: payload,
      );
      return false;
    }

    try {
      await scheduleWithMode(AndroidScheduleMode.inexactAllowWhileIdle);
      _managedNotificationIds.add(notificationId);
      return true;
    } on MissingPluginException {
      _available = false;
      return false;
    } on PlatformException {
      // Let the caller keep the schedule failure non-fatal when even the inexact
      // fallback is rejected by the platform.
    } catch (error, stackTrace) {
      _reportSchedulingError(
        error,
        stackTrace,
        notificationId: notificationId,
        payload: payload,
      );
      return false;
    }
    return false;
  }

  @override
  Future<void> cancel() async {
    await ensureInitialized();
    if (!_available) return;

    await _cancelManagedNotifications();
    _lastSuccessfulPlan = null;
  }

  Future<void> _cancelManagedNotifications() async {
    final notificationIds = _managedNotificationIds.isEmpty
        ? await _discoverManagedNotificationIds()
        : _managedNotificationIds.toSet();

    await _cancelNotificationBatch(
      notificationIds,
      clearManagedIds: true,
      allowFallbackRange: true,
    );
  }

  Future<Set<int>> _discoverManagedNotificationIds() async {
    final notificationIds = <int>{};
    try {
      final pending = await _plugin.pendingNotificationRequests();
      notificationIds.addAll(
        pending
            .where((request) => decodePayload(request.payload) != null)
            .map((request) => request.id),
      );
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      // ignore
    } catch (_) {
      // ignore
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        final active = await _plugin.getActiveNotifications();
        notificationIds.addAll(
          active
              .map((notification) => notification.id)
              .whereType<int>()
              .where(_isManagedNotificationId),
        );
      } on MissingPluginException {
        _available = false;
      } on PlatformException {
        // ignore
      } catch (_) {
        // ignore
      }
    }

    return notificationIds;
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

  Future<void> _cancelNotificationBatch(
    Set<int> notificationIds, {
    bool clearManagedIds = false,
    bool allowFallbackRange = false,
  }) async {
    if (notificationIds.isEmpty) {
      if (allowFallbackRange) {
        for (var i = 0; i < kReviewReminderMaxItems; i++) {
          await _cancelNotification(notificationIdBase + i);
        }
      }
      if (clearManagedIds) {
        _managedNotificationIds.clear();
      }
      return;
    }

    for (final notificationId in notificationIds) {
      await _cancelNotification(notificationId);
      if (!clearManagedIds) {
        _managedNotificationIds.remove(notificationId);
      }
    }
    if (clearManagedIds) {
      _managedNotificationIds.clear();
    }
  }

  Future<void> _rollbackScheduledBatch(
    List<int> scheduledNotificationIds,
  ) async {
    if (scheduledNotificationIds.isEmpty) {
      return;
    }

    for (final notificationId in scheduledNotificationIds.reversed) {
      await _cancelNotification(notificationId);
      _managedNotificationIds.remove(notificationId);
    }
  }

  Future<void> _markWindowsNotificationsUnavailableForRetry() async {
    _available = false;
    _initialized = false;
    await _disposeWindowsNotificationsPluginBestEffort();
  }

  Future<void> _disposeWindowsNotificationsPluginBestEffort() async {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    try {
      final windowsImpl = _plugin.resolvePlatformSpecificImplementation<
          FlutterLocalNotificationsWindows>();
      windowsImpl?.dispose();
    } catch (_) {
      // ignore
    }
  }

  Future<bool> _restorePreviousPlanIfNeeded(
    ReviewReminderPlan? previousPlan,
  ) async {
    if (previousPlan == null || previousPlan.items.isEmpty) {
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      await ensureInitialized();
      if (!_available) {
        return false;
      }
    }

    final restoredNotificationIds = <int>[];
    for (final item in previousPlan.items) {
      final notificationId = notificationIdForItem(item);
      final didRestore = await _scheduleSingleNotification(
        notificationId: notificationId,
        title: item.kind == ReviewReminderItemKind.reviewQueue
            ? t.actions.reviewQueue.title
            : t.actions.agenda.title,
        body: item.todoTitle,
        scheduleAt: tz.TZDateTime.from(
          DateTime.fromMillisecondsSinceEpoch(
            item.scheduleAtUtcMs,
            isUtc: true,
          ),
          tz.local,
        ),
        details: notificationDetailsForItem(item),
        payload: encodePayload(item),
      );
      if (!didRestore) {
        await _rollbackScheduledBatch(restoredNotificationIds);
        _lastSuccessfulPlan = null;
        if (defaultTargetPlatform == TargetPlatform.windows) {
          await _markWindowsNotificationsUnavailableForRetry();
        }
        return false;
      }
      restoredNotificationIds.add(notificationId);
    }

    _lastSuccessfulPlan = previousPlan;
    return true;
  }

  static int _stableHash(String input) {
    var value = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      value ^= codeUnit;
      value = (value * 0x01000193) & 0x7fffffff;
    }
    return value;
  }

  static bool _isManagedNotificationId(int notificationId) {
    return notificationId >= notificationIdBase &&
        notificationId < notificationIdBase + _managedNotificationIdModulo;
  }

  void _reportSchedulingError(
    Object error,
    StackTrace stackTrace, {
    required int notificationId,
    required String? payload,
  }) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'secondloop.notifications',
        context: ErrorDescription(
          'while scheduling review reminder system notification',
        ),
        informationCollector: () sync* {
          yield DiagnosticsProperty<int>('notificationId', notificationId);
          yield DiagnosticsProperty<String?>('payload', payload);
          yield DiagnosticsProperty<TargetPlatform>(
            'platform',
            defaultTargetPlatform,
          );
        },
      ),
    );
  }
}
